<#
.SYNOPSIS
    外付けHDDを検出し、Usersフォルダ内のユーザーを一覧化するモジュール

.DESCRIPTION
    - 接続された外付けドライブ（リムーバブル/固定）を列挙
    - 各ドライブ内の「Users」フォルダを自動検索
    - システムユーザー（Default, Public等）を除外してユーザー名を取得

.NOTES
    PowerShell 5.1 互換
    作成日: 2024
#>

#===============================================================================
# 除外するシステムユーザー一覧
#===============================================================================
$Script:ExcludedUsers = @(
    'Default',
    'Default User',
    'Public',
    'All Users',
    'Default.migrated',
    'desktop.ini',
    'NTUSER.DAT'
)

#===============================================================================
# 関数: Get-ExternalDrives
# 説明: 接続された外付けドライブを取得（C:ドライブは除外）
#===============================================================================
function Get-ExternalDrives {
    [CmdletBinding()]
    param()

    Write-Verbose "外付けドライブを検索中..."

    try {
        # 固定ディスクとリムーバブルディスクを取得（DriveType: 2=リムーバブル, 3=固定）
        $drives = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=2 OR DriveType=3" |
            Where-Object {
                # C:ドライブを除外、かつアクセス可能なドライブのみ
                $_.DeviceID -ne 'C:' -and
                (Test-Path -Path $_.DeviceID -ErrorAction SilentlyContinue)
            } |
            Select-Object -Property @{
                Name = 'DriveLetter'
                Expression = { $_.DeviceID }
            }, @{
                Name = 'VolumeName'
                Expression = { if ($_.VolumeName) { $_.VolumeName } else { '(名前なし)' } }
            }, @{
                Name = 'DriveType'
                Expression = {
                    switch ($_.DriveType) {
                        2 { 'リムーバブル' }
                        3 { '固定ディスク' }
                        default { '不明' }
                    }
                }
            }, @{
                Name = 'SizeGB'
                Expression = { [math]::Round($_.Size / 1GB, 2) }
            }, @{
                Name = 'FreeSpaceGB'
                Expression = { [math]::Round($_.FreeSpace / 1GB, 2) }
            }

        if ($drives) {
            Write-Verbose "検出されたドライブ数: $($drives.Count)"
            return $drives
        } else {
            Write-Warning "外付けドライブが見つかりませんでした"
            return @()
        }
    }
    catch {
        Write-Error "ドライブ検出エラー: $_"
        return @()
    }
}

#===============================================================================
# 関数: Find-UsersFolder
# 説明: 指定ドライブ内の「Users」フォルダを検索
#===============================================================================
function Find-UsersFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter,

        [Parameter(Mandatory = $false)]
        [ref]$AccessDeniedDetected = ([ref]$false)
    )

    Write-Verbose "ドライブ $DriveLetter 内のUsersフォルダを検索中..."

    # 検索対象のフォルダ名パターン（大文字小文字、日本語対応）
    $usersFolderNames = @("Users", "users", "User", "user", "ユーザー")

    # 検索対象のパスパターン（Windowsバックアップの一般的な構造）
    # R-Studio等のデータ復旧ソフトで救出した場合、深い階層にある可能性あり
    $searchPaths = @()

    foreach ($folderName in $usersFolderNames) {
        $searchPaths += @(
            "$DriveLetter\$folderName",                    # 直接
            "$DriveLetter\Backup\$folderName",             # Backupフォルダ内
            "$DriveLetter\WindowsBackup\$folderName",      # WindowsBackup内
            "$DriveLetter\*\$folderName",                  # 1階層下
            "$DriveLetter\*\*\$folderName",                # 2階層下
            "$DriveLetter\*\*\*\$folderName"               # 3階層下（R-Studio復旧等）
        )
    }

    $foundPaths = @()

    foreach ($pattern in $searchPaths) {
        try {
            # ワイルドカードを含むパターンの場合
            if ($pattern -like '*`**') {
                $resolved = Get-ChildItem -Path $pattern -Directory -ErrorAction Stop 2>&1
                foreach ($item in $resolved) {
                    if ($item -is [System.IO.DirectoryInfo]) {
                        if (Test-Path -Path $item.FullName) {
                            $foundPaths += $item.FullName
                            Write-Verbose "Usersフォルダ発見: $($item.FullName)"
                        }
                    }
                }
            }
            else {
                # 直接パスの場合
                if (Test-Path -Path $pattern -PathType Container) {
                    $foundPaths += $pattern
                    Write-Verbose "Usersフォルダ発見: $pattern"
                }
            }
        }
        catch {
            if ($_.Exception.Message -like "*アクセスが拒否*" -or
                $_.Exception.Message -like "*Access*denied*" -or
                $_.Exception.Message -like "*UnauthorizedAccess*") {
                if ($AccessDeniedDetected) {
                    $AccessDeniedDetected.Value = $true
                }
                Write-Verbose "アクセス拒否: $pattern"
            }
            else {
                Write-Verbose "パス検索エラー ($pattern): $_"
            }
        }
    }

    return $foundPaths | Select-Object -Unique
}

#===============================================================================
# 関数: Test-IsUserProfileFolder
# 説明: 指定フォルダがユーザープロファイルフォルダかチェック
#       （Desktop, Documents, AppData等が存在するか確認）
#===============================================================================
function Test-IsUserProfileFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FolderPath
    )

    if (-not (Test-Path -Path $FolderPath -PathType Container)) {
        return $false
    }

    # ユーザープロファイルに典型的なフォルダをチェック
    $profileIndicators = @("Desktop", "Documents", "AppData")
    $foundCount = 0

    foreach ($indicator in $profileIndicators) {
        $checkPath = Join-Path -Path $FolderPath -ChildPath $indicator
        if (Test-Path -Path $checkPath -PathType Container) {
            $foundCount++
        }
    }

    # 2つ以上あればユーザープロファイルと判定
    return ($foundCount -ge 2)
}

#===============================================================================
# 関数: Find-DirectUserProfiles
# 説明: Usersフォルダなしで直接ユーザープロファイルを検索
#       （R-Studioで復旧した場合等に対応）
#===============================================================================
function Find-DirectUserProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )

    Write-Verbose "直接ユーザープロファイルを検索中..."

    $foundProfiles = @()

    # 3階層下まで検索（時間がかかる可能性あり）
    $searchDepths = @(
        "$DriveLetter\*",
        "$DriveLetter\*\*",
        "$DriveLetter\*\*\*"
    )

    foreach ($pattern in $searchDepths) {
        try {
            $folders = Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue
            foreach ($folder in $folders) {
                # システムフォルダや除外フォルダをスキップ
                if ($folder.Name -in $Script:ExcludedUsers) { continue }
                if ($folder.Name -like '$*') { continue }  # $RECYCLE.BIN等
                if ($folder.Name -eq 'System Volume Information') { continue }
                if ($folder.Name -eq 'Windows') { continue }
                if ($folder.Name -eq 'Program Files') { continue }
                if ($folder.Name -eq 'Program Files (x86)') { continue }

                # ユーザープロファイルかチェック
                if (Test-IsUserProfileFolder -FolderPath $folder.FullName) {
                    Write-Verbose "直接ユーザープロファイル発見: $($folder.FullName)"
                    $foundProfiles += $folder.FullName
                }
            }
        }
        catch {
            Write-Verbose "検索エラー ($pattern): $_"
        }
    }

    return $foundProfiles | Select-Object -Unique
}

#===============================================================================
# 関数: Get-BackupUsers
# 説明: Usersフォルダ内のユーザー一覧を取得（システムユーザー除外）
#===============================================================================
function Get-BackupUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UsersPath
    )

    Write-Verbose "ユーザーフォルダをスキャン中: $UsersPath"

    try {
        $users = Get-ChildItem -Path $UsersPath -Directory -ErrorAction Stop |
            Where-Object {
                # システムユーザーを除外
                $_.Name -notin $Script:ExcludedUsers -and
                # 隠しフォルダを除外
                -not $_.Attributes.HasFlag([System.IO.FileAttributes]::Hidden)
            } |
            Select-Object -Property @{
                Name = 'UserName'
                Expression = { $_.Name }
            }, @{
                Name = 'FullPath'
                Expression = { $_.FullName }
            }, @{
                Name = 'LastWriteTime'
                Expression = { $_.LastWriteTime }
            }, @{
                Name = 'HasDesktop'
                Expression = { Test-Path -Path (Join-Path $_.FullName 'Desktop') }
            }, @{
                Name = 'HasDocuments'
                Expression = { Test-Path -Path (Join-Path $_.FullName 'Documents') }
            }, @{
                Name = 'HasAppData'
                Expression = { Test-Path -Path (Join-Path $_.FullName 'AppData') }
            }

        if ($users) {
            Write-Verbose "検出されたユーザー数: $($users.Count)"
            return $users
        } else {
            Write-Warning "ユーザーが見つかりませんでした: $UsersPath"
            return @()
        }
    }
    catch {
        Write-Error "ユーザースキャンエラー: $_"
        return @()
    }
}

#===============================================================================
# 関数: Show-ManualPathDialog
# 説明: 手動でユーザーフォルダを指定するダイアログ
#===============================================================================
function Show-ManualPathDialog {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms

    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "ユーザープロファイルフォルダを選択してください`n（Desktop, Documents等があるフォルダ）"
    $folderBrowser.ShowNewFolderButton = $false

    $result = $folderBrowser.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $folderBrowser.SelectedPath
    }

    return $null
}

#===============================================================================
# 関数: Scan-AllBackupDrives
# 説明: すべての外付けドライブをスキャンし、バックアップユーザーを一覧化
#===============================================================================
function Scan-AllBackupDrives {
    [CmdletBinding()]
    param()

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " バックアップドライブスキャン開始" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $results = @()

    # 外付けドライブを取得
    $drives = Get-ExternalDrives

    if (-not $drives -or $drives.Count -eq 0) {
        Write-Host "`n[警告] 外付けドライブが検出されませんでした" -ForegroundColor Yellow
        Write-Host "外付けHDDが正しく接続されているか確認してください" -ForegroundColor Yellow
        return @()
    }

    Write-Host "`n検出されたドライブ:" -ForegroundColor Green
    foreach ($drive in $drives) {
        Write-Host "  $($drive.DriveLetter) - $($drive.VolumeName) ($($drive.DriveType), $($drive.SizeGB)GB)" -ForegroundColor White
    }

    # アクセス拒否検出フラグ
    $accessDeniedFlag = $false

    # 各ドライブのUsersフォルダを検索
    foreach ($drive in $drives) {
        Write-Host "`n$($drive.DriveLetter) をスキャン中..." -ForegroundColor Yellow

        # 1. まずUsersフォルダを検索
        $usersFolders = Find-UsersFolder -DriveLetter $drive.DriveLetter -AccessDeniedDetected ([ref]$accessDeniedFlag)

        foreach ($usersPath in $usersFolders) {
            Write-Host "  Usersフォルダ発見: $usersPath" -ForegroundColor Green

            $users = Get-BackupUsers -UsersPath $usersPath

            foreach ($user in $users) {
                # 結果オブジェクトを作成
                $results += [PSCustomObject]@{
                    DriveLetter    = $drive.DriveLetter
                    VolumeName     = $drive.VolumeName
                    UsersPath      = $usersPath
                    UserName       = $user.UserName
                    UserFullPath   = $user.FullPath
                    LastWriteTime  = $user.LastWriteTime
                    HasDesktop     = $user.HasDesktop
                    HasDocuments   = $user.HasDocuments
                    HasAppData     = $user.HasAppData
                }

                # ユーザー情報を表示
                $status = @()
                if ($user.HasDesktop) { $status += "Desktop" }
                if ($user.HasDocuments) { $status += "Documents" }
                if ($user.HasAppData) { $status += "AppData" }

                Write-Host "    [ユーザー] $($user.UserName)" -ForegroundColor Cyan
                Write-Host "      フォルダ: $($status -join ', ')" -ForegroundColor Gray
            }
        }

        # 2. Usersフォルダが見つからない場合、直接ユーザープロファイルを検索
        if ($usersFolders.Count -eq 0) {
            Write-Host "  Usersフォルダが見つかりません。直接ユーザープロファイルを検索中..." -ForegroundColor Yellow

            $directProfiles = Find-DirectUserProfiles -DriveLetter $drive.DriveLetter

            foreach ($profilePath in $directProfiles) {
                $folderName = Split-Path -Path $profilePath -Leaf
                $parentPath = Split-Path -Path $profilePath -Parent

                Write-Host "  直接ユーザープロファイル発見: $profilePath" -ForegroundColor Green

                $results += [PSCustomObject]@{
                    DriveLetter    = $drive.DriveLetter
                    VolumeName     = $drive.VolumeName
                    UsersPath      = $parentPath
                    UserName       = $folderName
                    UserFullPath   = $profilePath
                    LastWriteTime  = (Get-Item $profilePath).LastWriteTime
                    HasDesktop     = Test-Path (Join-Path $profilePath 'Desktop')
                    HasDocuments   = Test-Path (Join-Path $profilePath 'Documents')
                    HasAppData     = Test-Path (Join-Path $profilePath 'AppData')
                }

                Write-Host "    [ユーザー] $folderName" -ForegroundColor Cyan
            }
        }
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " スキャン完了: $($results.Count) ユーザー検出" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # アクセス拒否が検出された場合の警告
    if ($accessDeniedFlag) {
        Write-Host "`n[警告] 一部のフォルダにアクセス権限がありません" -ForegroundColor Yellow
        Write-Host "外部HDDから復旧する場合は、復元画面で「外部HDD復旧モード」を有効にしてください" -ForegroundColor Yellow
        Write-Host "（管理者権限で実行することで、アクセス制限を回避できます）" -ForegroundColor Yellow
    }

    # 3. 見つからない場合、手動指定オプションを提示
    if ($results.Count -eq 0) {
        Write-Host "`n[情報] ユーザーフォルダが自動検出できませんでした" -ForegroundColor Yellow

        Add-Type -AssemblyName System.Windows.Forms

        $manualDialogMessage = "ユーザーフォルダが自動検出できませんでした。`n`n手動でユーザープロファイルフォルダを指定しますか？`n（Desktop, Documents等があるフォルダを選択）"
        if ($accessDeniedFlag) {
            $manualDialogMessage += "`n`n※アクセス権限の問題が検出されました。`n復元時は「外部HDD復旧モード」を有効にしてください。"
        }

        $dialogResult = [System.Windows.Forms.MessageBox]::Show(
            $manualDialogMessage,
            "手動指定",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            $manualPath = Show-ManualPathDialog

            if ($manualPath -and (Test-Path $manualPath)) {
                # 手動指定されたパスがユーザープロファイルかチェック
                if (Test-IsUserProfileFolder -FolderPath $manualPath) {
                    $folderName = Split-Path -Path $manualPath -Leaf
                    $parentPath = Split-Path -Path $manualPath -Parent
                    $driveLetter = (Split-Path -Path $manualPath -Qualifier)

                    Write-Host "`n手動指定されたユーザープロファイル: $manualPath" -ForegroundColor Green

                    $results += [PSCustomObject]@{
                        DriveLetter    = $driveLetter
                        VolumeName     = "(手動指定)"
                        UsersPath      = $parentPath
                        UserName       = $folderName
                        UserFullPath   = $manualPath
                        LastWriteTime  = (Get-Item $manualPath).LastWriteTime
                        HasDesktop     = Test-Path (Join-Path $manualPath 'Desktop')
                        HasDocuments   = Test-Path (Join-Path $manualPath 'Documents')
                        HasAppData     = Test-Path (Join-Path $manualPath 'AppData')
                    }
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show(
                        "指定されたフォルダはユーザープロファイルではないようです。`n`nDesktop, Documents, AppData等のフォルダが含まれているフォルダを選択してください。",
                        "エラー",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                }
            }
        }
    }

    return $results
}

#===============================================================================
# エクスポート（モジュールとして使用する場合）
#===============================================================================
# Export-ModuleMember -Function Get-ExternalDrives, Find-UsersFolder, Get-BackupUsers, Scan-AllBackupDrives

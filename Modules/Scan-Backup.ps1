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
        [string]$DriveLetter
    )

    Write-Verbose "ドライブ $DriveLetter 内のUsersフォルダを検索中..."

    # 検索対象のパスパターン（Windowsバックアップの一般的な構造）
    $searchPaths = @(
        "$DriveLetter\Users",                          # 直接Users
        "$DriveLetter\Backup\Users",                   # Backupフォルダ内
        "$DriveLetter\WindowsBackup\Users",            # WindowsBackup内
        "$DriveLetter\*\Users"                         # 1階層下
    )

    $foundPaths = @()

    foreach ($pattern in $searchPaths) {
        try {
            # ワイルドカードを含むパターンの場合
            if ($pattern -like '*`**') {
                $resolved = Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue
                foreach ($item in $resolved) {
                    if (Test-Path -Path $item.FullName) {
                        $foundPaths += $item.FullName
                        Write-Verbose "Usersフォルダ発見: $($item.FullName)"
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
            Write-Verbose "パス検索エラー ($pattern): $_"
        }
    }

    return $foundPaths | Select-Object -Unique
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

    # 各ドライブのUsersフォルダを検索
    foreach ($drive in $drives) {
        Write-Host "`n$($drive.DriveLetter) をスキャン中..." -ForegroundColor Yellow

        $usersFolders = Find-UsersFolder -DriveLetter $drive.DriveLetter

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
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " スキャン完了: $($results.Count) ユーザー検出" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    return $results
}

#===============================================================================
# エクスポート（モジュールとして使用する場合）
#===============================================================================
# Export-ModuleMember -Function Get-ExternalDrives, Find-UsersFolder, Get-BackupUsers, Scan-AllBackupDrives

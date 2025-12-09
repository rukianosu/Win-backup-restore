<#
.SYNOPSIS
    robocopyを使用してユーザーデータをバックアップするモジュール

.DESCRIPTION
    - 現在のユーザーフォルダを外付けHDDにバックアップ
    - Desktop, Documents, Pictures, Videos, Music, Downloads をコピー
    - AppData内の辞書・テーマをバックアップ
    - OneDrive, Dropbox等のクラウドドライブもバックアップ
    - Edge/Chromeのブックマークをバックアップ

.NOTES
    PowerShell 5.1 互換
    robocopy使用
#>

#===============================================================================
# グローバル設定
#===============================================================================
$Script:BackupLogPath = "C:\AutoSetup\Logs\Backup.log"

#===============================================================================
# バックアップ対象フォルダ定義
#===============================================================================
$Script:StandardFolders = @(
    @{ Name = "Desktop";    FolderName = "Desktop" },
    @{ Name = "Documents";  FolderName = "Documents" },
    @{ Name = "Pictures";   FolderName = "Pictures" },
    @{ Name = "Videos";     FolderName = "Videos" },
    @{ Name = "Music";      FolderName = "Music" },
    @{ Name = "Downloads";  FolderName = "Downloads" }
)

$Script:AppDataFolders = @(
    @{
        Name       = "辞書（Dictionaries）"
        FolderPath = "AppData\Roaming\Microsoft\Windows\Dictionaries"
    },
    @{
        Name       = "テーマ（Themes）"
        FolderPath = "AppData\Roaming\Microsoft\Windows\Themes"
    }
)

$Script:CloudDriveFolders = @(
    @{ Name = "OneDrive";     FolderName = "OneDrive" },
    @{ Name = "Dropbox";      FolderName = "Dropbox" },
    @{ Name = "iCloudDrive";  FolderName = "iCloudDrive" },
    @{ Name = "GoogleDrive";  FolderName = "Google Drive" },
    @{ Name = "GoogleDrive2"; FolderName = "GoogleDrive" }
)

#===============================================================================
# ブラウザデータ定義（お気に入り、履歴、オートフィル、設定）
#===============================================================================
$Script:BrowserData = @(
    # Microsoft Edge
    @{
        Name       = "Edge - お気に入り"
        Browser    = "Edge"
        SourcePath = "AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks"
        TargetPath = "AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks"
    },
    @{
        Name       = "Edge - 閲覧履歴"
        Browser    = "Edge"
        SourcePath = "AppData\Local\Microsoft\Edge\User Data\Default\History"
        TargetPath = "AppData\Local\Microsoft\Edge\User Data\Default\History"
    },
    @{
        Name       = "Edge - オートフィル"
        Browser    = "Edge"
        SourcePath = "AppData\Local\Microsoft\Edge\User Data\Default\Web Data"
        TargetPath = "AppData\Local\Microsoft\Edge\User Data\Default\Web Data"
    },
    @{
        Name       = "Edge - 設定"
        Browser    = "Edge"
        SourcePath = "AppData\Local\Microsoft\Edge\User Data\Default\Preferences"
        TargetPath = "AppData\Local\Microsoft\Edge\User Data\Default\Preferences"
    },
    # Google Chrome
    @{
        Name       = "Chrome - お気に入り"
        Browser    = "Chrome"
        SourcePath = "AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
        TargetPath = "AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
    },
    @{
        Name       = "Chrome - 閲覧履歴"
        Browser    = "Chrome"
        SourcePath = "AppData\Local\Google\Chrome\User Data\Default\History"
        TargetPath = "AppData\Local\Google\Chrome\User Data\Default\History"
    },
    @{
        Name       = "Chrome - オートフィル"
        Browser    = "Chrome"
        SourcePath = "AppData\Local\Google\Chrome\User Data\Default\Web Data"
        TargetPath = "AppData\Local\Google\Chrome\User Data\Default\Web Data"
    },
    @{
        Name       = "Chrome - 設定"
        Browser    = "Chrome"
        SourcePath = "AppData\Local\Google\Chrome\User Data\Default\Preferences"
        TargetPath = "AppData\Local\Google\Chrome\User Data\Default\Preferences"
    }
)

#===============================================================================
# 関数: Write-BackupLog
# 説明: ログファイルに書き込み
#===============================================================================
function Write-BackupLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'SKIP')]
        [string]$Level = 'INFO'
    )

    # ログディレクトリ作成
    $logDir = Split-Path -Path $Script:BackupLogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # タイムスタンプ付きでログ出力
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # ファイルとコンソールに出力
    Add-Content -Path $Script:BackupLogPath -Value $logEntry -Encoding UTF8

    # コンソール出力（色分け）
    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        'SKIP'    { 'Gray' }
        default   { 'White' }
    }
    Write-Host $logEntry -ForegroundColor $color
}

#===============================================================================
# 関数: Invoke-BackupRobocopy
# 説明: robocopyでバックアップを実行
#===============================================================================
function Invoke-BackupRobocopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $false)]
        [string]$FolderName = ""
    )

    # ソースフォルダ存在チェック
    if (-not (Test-Path -Path $Source)) {
        Write-BackupLog -Message "[$FolderName] ソースフォルダが存在しません: $Source" -Level 'SKIP'
        return @{
            Success = $false
            Skipped = $true
            Error = $false
            Message = "ソースフォルダなし"
        }
    }

    # 宛先フォルダの親ディレクトリ作成
    $destParent = Split-Path -Path $Destination -Parent
    if (-not (Test-Path -Path $destParent)) {
        New-Item -Path $destParent -ItemType Directory -Force | Out-Null
    }

    Write-BackupLog -Message "[$FolderName] バックアップ開始: $Source -> $Destination" -Level 'INFO'

    try {
        # robocopyオプション設定
        $robocopyArgs = @(
            "`"$Source`"",
            "`"$Destination`"",
            "/E",           # 空のサブディレクトリも含めてコピー
            "/COPY:DAT",    # データ、属性、タイムスタンプをコピー
            "/R:3",         # リトライ回数
            "/W:5",         # リトライ間隔（秒）
            "/MT:8",        # マルチスレッド
            "/NP",          # 進捗表示なし
            "/XJ",          # ジャンクションを除外
            "/XA:SH"        # システム・隠しファイルを除外
        )

        $argString = $robocopyArgs -join " "
        $result = cmd /c "robocopy $argString 2>&1"
        $exitCode = $LASTEXITCODE

        # robocopy終了コードの解釈
        if ($exitCode -lt 8) {
            Write-BackupLog -Message "[$FolderName] バックアップ完了 (終了コード: $exitCode)" -Level 'SUCCESS'
            return @{
                Success = $true
                Skipped = $false
                Error = $false
                Message = "バックアップ完了"
                ExitCode = $exitCode
            }
        }
        else {
            Write-BackupLog -Message "[$FolderName] バックアップエラー (終了コード: $exitCode)" -Level 'ERROR'
            return @{
                Success = $false
                Skipped = $false
                Error = $true
                Message = "robocopyエラー: $exitCode"
                ExitCode = $exitCode
            }
        }
    }
    catch {
        Write-BackupLog -Message "[$FolderName] 例外エラー: $_" -Level 'ERROR'
        return @{
            Success = $false
            Skipped = $false
            Error = $true
            Message = $_.Exception.Message
        }
    }
}

#===============================================================================
# 関数: Backup-StandardFolders
# 説明: 標準フォルダ（Desktop, Documents等）をバックアップ
#===============================================================================
function Backup-StandardFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupBasePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    $currentUserProfile = $env:USERPROFILE

    Write-BackupLog -Message "=== 標準フォルダのバックアップ開始 ===" -Level 'INFO'

    foreach ($folder in $Script:StandardFolders) {
        # オプションチェック
        $optionName = "Backup$($folder.Name)"
        if ($Options.ContainsKey($optionName) -and -not $Options[$optionName]) {
            Write-BackupLog -Message "[$($folder.Name)] オプションでスキップ" -Level 'SKIP'
            $results.Skipped++
            continue
        }

        $sourcePath = Join-Path -Path $currentUserProfile -ChildPath $folder.FolderName
        $destPath = Join-Path -Path $BackupBasePath -ChildPath $folder.FolderName

        $copyResult = Invoke-BackupRobocopy -Source $sourcePath -Destination $destPath -FolderName $folder.Name

        if ($copyResult.Success) {
            $results.Success++
        }
        elseif ($copyResult.Skipped) {
            $results.Skipped++
        }
        else {
            $results.Errors++
        }
    }

    return $results
}

#===============================================================================
# 関数: Backup-AppDataFolders
# 説明: AppData内のフォルダ（辞書・テーマ）をバックアップ
#===============================================================================
function Backup-AppDataFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupBasePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    # AppDataバックアップオプションチェック
    if ($Options.ContainsKey('BackupAppData') -and -not $Options['BackupAppData']) {
        Write-BackupLog -Message "AppDataバックアップがオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    $currentUserProfile = $env:USERPROFILE

    Write-BackupLog -Message "=== AppDataフォルダのバックアップ開始 ===" -Level 'INFO'

    foreach ($folder in $Script:AppDataFolders) {
        $sourcePath = Join-Path -Path $currentUserProfile -ChildPath $folder.FolderPath
        $destPath = Join-Path -Path $BackupBasePath -ChildPath $folder.FolderPath

        $copyResult = Invoke-BackupRobocopy -Source $sourcePath -Destination $destPath -FolderName $folder.Name

        if ($copyResult.Success) {
            $results.Success++
        }
        elseif ($copyResult.Skipped) {
            $results.Skipped++
        }
        else {
            $results.Errors++
        }
    }

    return $results
}

#===============================================================================
# 関数: Backup-CloudDriveFolders
# 説明: クラウドドライブフォルダをバックアップ（存在する場合のみ）
#===============================================================================
function Backup-CloudDriveFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupBasePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    # クラウドドライブバックアップオプションチェック
    if ($Options.ContainsKey('BackupCloudDrive') -and -not $Options['BackupCloudDrive']) {
        Write-BackupLog -Message "クラウドドライブバックアップがオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    $currentUserProfile = $env:USERPROFILE

    Write-BackupLog -Message "=== クラウドドライブのバックアップ開始 ===" -Level 'INFO'

    foreach ($folder in $Script:CloudDriveFolders) {
        $sourcePath = Join-Path -Path $currentUserProfile -ChildPath $folder.FolderName

        # 存在チェック
        if (-not (Test-Path -Path $sourcePath)) {
            continue
        }

        $destPath = Join-Path -Path $BackupBasePath -ChildPath $folder.FolderName

        Write-BackupLog -Message "[$($folder.Name)] クラウドドライブ発見: $sourcePath" -Level 'INFO'

        $copyResult = Invoke-BackupRobocopy -Source $sourcePath -Destination $destPath -FolderName $folder.Name

        if ($copyResult.Success) {
            $results.Success++
        }
        elseif ($copyResult.Skipped) {
            $results.Skipped++
        }
        else {
            $results.Errors++
        }
    }

    return $results
}

#===============================================================================
# 関数: Backup-BrowserData
# 説明: Edge/Chromeのブラウザデータをバックアップ
#       （お気に入り、閲覧履歴、オートフィル、設定）
#===============================================================================
function Backup-BrowserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupBasePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    # ブラウザデータバックアップオプションチェック
    if ($Options.ContainsKey('BackupBookmarks') -and -not $Options['BackupBookmarks']) {
        Write-BackupLog -Message "ブラウザデータバックアップがオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    $currentUserProfile = $env:USERPROFILE

    Write-BackupLog -Message "=== ブラウザデータのバックアップ開始 ===" -Level 'INFO'
    Write-BackupLog -Message "（お気に入り、閲覧履歴、オートフィル、設定）" -Level 'INFO'

    foreach ($item in $Script:BrowserData) {
        $sourcePath = Join-Path -Path $currentUserProfile -ChildPath $item.SourcePath

        if (-not (Test-Path -Path $sourcePath)) {
            Write-BackupLog -Message "[$($item.Name)] ファイルが見つかりません" -Level 'SKIP'
            $results.Skipped++
            continue
        }

        $destPath = Join-Path -Path $BackupBasePath -ChildPath $item.TargetPath
        $destDir = Split-Path -Path $destPath -Parent

        # 宛先ディレクトリ作成
        if (-not (Test-Path -Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        try {
            Copy-Item -Path $sourcePath -Destination $destPath -Force
            Write-BackupLog -Message "[$($item.Name)] バックアップ完了" -Level 'SUCCESS'
            $results.Success++
        }
        catch {
            Write-BackupLog -Message "[$($item.Name)] バックアップ失敗: $_" -Level 'ERROR'
            $results.Errors++
        }
    }

    return $results
}

# 後方互換性のためのエイリアス
function Backup-BrowserBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupBasePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    return Backup-BrowserData -BackupBasePath $BackupBasePath -Options $Options
}

#===============================================================================
# 関数: Backup-AllUserData
# 説明: すべてのユーザーデータをバックアップ（メイン関数）
#===============================================================================
function Backup-AllUserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupBasePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $totalResults = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    Write-BackupLog -Message "========================================" -Level 'INFO'
    Write-BackupLog -Message "ユーザーデータバックアップ処理開始" -Level 'INFO'
    Write-BackupLog -Message "バックアップ先: $BackupBasePath" -Level 'INFO'
    Write-BackupLog -Message "========================================" -Level 'INFO'

    # 標準フォルダをバックアップ
    $standardResult = Backup-StandardFolders -BackupBasePath $BackupBasePath -Options $Options
    $totalResults.Success += $standardResult.Success
    $totalResults.Skipped += $standardResult.Skipped
    $totalResults.Errors += $standardResult.Errors

    # AppDataフォルダをバックアップ
    $appDataResult = Backup-AppDataFolders -BackupBasePath $BackupBasePath -Options $Options
    $totalResults.Success += $appDataResult.Success
    $totalResults.Skipped += $appDataResult.Skipped
    $totalResults.Errors += $appDataResult.Errors

    # クラウドドライブをバックアップ
    $cloudResult = Backup-CloudDriveFolders -BackupBasePath $BackupBasePath -Options $Options
    $totalResults.Success += $cloudResult.Success
    $totalResults.Skipped += $cloudResult.Skipped
    $totalResults.Errors += $cloudResult.Errors

    # ブックマークをバックアップ
    $bookmarkResult = Backup-BrowserBookmarks -BackupBasePath $BackupBasePath -Options $Options
    $totalResults.Success += $bookmarkResult.Success
    $totalResults.Skipped += $bookmarkResult.Skipped
    $totalResults.Errors += $bookmarkResult.Errors

    Write-BackupLog -Message "" -Level 'INFO'
    Write-BackupLog -Message "========================================" -Level 'INFO'
    Write-BackupLog -Message "ユーザーデータバックアップ処理完了" -Level 'INFO'
    Write-BackupLog -Message "成功: $($totalResults.Success), スキップ: $($totalResults.Skipped), エラー: $($totalResults.Errors)" -Level 'INFO'
    Write-BackupLog -Message "========================================" -Level 'INFO'

    return $totalResults
}

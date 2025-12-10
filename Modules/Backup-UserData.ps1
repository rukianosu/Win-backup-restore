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
# 関数: Test-BackupDriveAvailable
# 説明: バックアップ先ドライブが利用可能かチェック
#===============================================================================
function Test-BackupDriveAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        # パスからドライブ文字を取得
        if ($Path -match '^([A-Za-z]):') {
            $driveLetter = $Matches[1]
            $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
            if (-not $drive) {
                return $false
            }
            # ドライブにアクセスできるか確認
            $testPath = "${driveLetter}:\"
            if (-not (Test-Path -Path $testPath -ErrorAction SilentlyContinue)) {
                return $false
            }
            return $true
        }
        # UNCパスなどの場合はTest-Pathで確認
        $parentPath = Split-Path -Path $Path -Parent
        if ($parentPath -and -not (Test-Path -Path $parentPath -ErrorAction SilentlyContinue)) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
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
            "/Z",           # 再開可能モード（中断しても続きから）
            "/COPY:DAT",    # データ、属性、タイムスタンプをコピー
            "/DCOPY:T",     # ディレクトリのタイムスタンプもコピー
            "/R:3",         # リトライ回数
            "/W:5",         # リトライ間隔（秒）
            "/MT:8",        # マルチスレッド
            "/NP",          # 進捗表示なし
            "/XJ",          # ジャンクションを除外
            "/XA:SH",       # システム・隠しファイルを除外
            "/XO"           # 古いファイルを除外（変更なしはスキップ）
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

        # バックアップ先ドライブの存在チェック
        if (-not (Test-BackupDriveAvailable -Path $BackupBasePath)) {
            Write-BackupLog -Message "[$($folder.Name)] バックアップ先ドライブが見つかりません。バックアップを中止します。" -Level 'ERROR'
            throw "バックアップ先ドライブが切断されました: $BackupBasePath"
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
        # バックアップ先ドライブの存在チェック
        if (-not (Test-BackupDriveAvailable -Path $BackupBasePath)) {
            Write-BackupLog -Message "[$($folder.Name)] バックアップ先ドライブが見つかりません。バックアップを中止します。" -Level 'ERROR'
            throw "バックアップ先ドライブが切断されました: $BackupBasePath"
        }

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

        # バックアップ先ドライブの存在チェック
        if (-not (Test-BackupDriveAvailable -Path $BackupBasePath)) {
            Write-BackupLog -Message "[$($folder.Name)] バックアップ先ドライブが見つかりません。バックアップを中止します。" -Level 'ERROR'
            throw "バックアップ先ドライブが切断されました: $BackupBasePath"
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
# 関数: Close-Browsers
# 説明: Edge/Chromeを終了する（バックグラウンドプロセスも含む）
#===============================================================================
function Close-Browsers {
    [CmdletBinding()]
    param()

    $closed = @{
        Edge = $false
        Chrome = $false
    }

    # Microsoft Edge を終了（関連プロセスもすべて終了）
    $edgeProcessNames = @("msedge", "msedgewebview2", "MicrosoftEdgeUpdate")
    $edgeProcesses = Get-Process -Name $edgeProcessNames -ErrorAction SilentlyContinue
    if ($edgeProcesses) {
        Write-BackupLog -Message "Microsoft Edge を終了中..." -Level 'INFO'
        try {
            # まず通常終了を試みる
            $mainEdge = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
            if ($mainEdge) {
                $mainEdge | ForEach-Object { $_.CloseMainWindow() | Out-Null }
                Start-Sleep -Seconds 3
            }

            # 残っているプロセスを強制終了
            $remainingEdge = Get-Process -Name $edgeProcessNames -ErrorAction SilentlyContinue
            if ($remainingEdge) {
                $remainingEdge | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            Write-BackupLog -Message "Microsoft Edge を終了しました" -Level 'SUCCESS'
            $closed.Edge = $true
        }
        catch {
            Write-BackupLog -Message "Microsoft Edge の終了に失敗: $_" -Level 'WARNING'
        }
    }

    # Google Chrome を終了（関連プロセスもすべて終了）
    $chromeProcessNames = @("chrome", "GoogleUpdate", "GoogleCrashHandler", "GoogleCrashHandler64")
    $chromeProcesses = Get-Process -Name $chromeProcessNames -ErrorAction SilentlyContinue
    if ($chromeProcesses) {
        Write-BackupLog -Message "Google Chrome を終了中..." -Level 'INFO'
        try {
            # まず通常終了を試みる
            $mainChrome = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
            if ($mainChrome) {
                $mainChrome | ForEach-Object { $_.CloseMainWindow() | Out-Null }
                Start-Sleep -Seconds 3
            }

            # 残っているプロセスを強制終了
            $remainingChrome = Get-Process -Name $chromeProcessNames -ErrorAction SilentlyContinue
            if ($remainingChrome) {
                $remainingChrome | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            Write-BackupLog -Message "Google Chrome を終了しました" -Level 'SUCCESS'
            $closed.Chrome = $true
        }
        catch {
            Write-BackupLog -Message "Google Chrome の終了に失敗: $_" -Level 'WARNING'
        }
    }

    # 追加の待機（ファイルロック解除のため）
    if ($closed.Edge -or $closed.Chrome) {
        Write-BackupLog -Message "ファイルロック解除を待機中..." -Level 'INFO'
        Start-Sleep -Seconds 3
    }

    return $closed
}

#===============================================================================
# 関数: Test-BrowserRunning
# 説明: ブラウザが起動中かチェック
#===============================================================================
function Test-BrowserRunning {
    [CmdletBinding()]
    param()

    $running = @{
        Edge = $false
        Chrome = $false
    }

    $running.Edge = $null -ne (Get-Process -Name "msedge" -ErrorAction SilentlyContinue)
    $running.Chrome = $null -ne (Get-Process -Name "chrome" -ErrorAction SilentlyContinue)

    return $running
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

    # ブラウザ自動終了オプションがONの場合
    if ($Options.ContainsKey('CloseBrowsers') -and $Options['CloseBrowsers']) {
        $browserStatus = Test-BrowserRunning
        if ($browserStatus.Edge -or $browserStatus.Chrome) {
            Write-BackupLog -Message "ブラウザを自動終了します..." -Level 'INFO'
            $closedBrowsers = Close-Browsers
            # ファイルロック解除のため少し待機
            Start-Sleep -Seconds 2
        }
    }
    else {
        # 自動終了しない場合は警告
        $browserStatus = Test-BrowserRunning
        if ($browserStatus.Edge) {
            Write-BackupLog -Message "警告: Microsoft Edge が起動中です。一部のファイルがコピーできない可能性があります" -Level 'WARNING'
        }
        if ($browserStatus.Chrome) {
            Write-BackupLog -Message "警告: Google Chrome が起動中です。一部のファイルがコピーできない可能性があります" -Level 'WARNING'
        }
    }

    foreach ($item in $Script:BrowserData) {
        $sourcePath = Join-Path -Path $currentUserProfile -ChildPath $item.SourcePath

        if (-not (Test-Path -Path $sourcePath)) {
            Write-BackupLog -Message "[$($item.Name)] ファイルが見つかりません" -Level 'SKIP'
            $results.Skipped++
            continue
        }

        # バックアップ先ドライブの存在チェック
        if (-not (Test-BackupDriveAvailable -Path $BackupBasePath)) {
            Write-BackupLog -Message "[$($item.Name)] バックアップ先ドライブが見つかりません。バックアップを中止します。" -Level 'ERROR'
            throw "バックアップ先ドライブが切断されました: $BackupBasePath"
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
    Write-Host "`n  [1/5] 標準フォルダをバックアップ中..." -ForegroundColor Cyan
    Write-Progress -Activity "ユーザーデータバックアップ" -Status "標準フォルダ (Desktop, Documents等)..." -PercentComplete 10
    $standardResult = Backup-StandardFolders -BackupBasePath $BackupBasePath -Options $Options
    $totalResults.Success += $standardResult.Success
    $totalResults.Skipped += $standardResult.Skipped
    $totalResults.Errors += $standardResult.Errors

    # AppDataフォルダをバックアップ
    Write-Host "  [2/5] AppDataをバックアップ中..." -ForegroundColor Cyan
    Write-Progress -Activity "ユーザーデータバックアップ" -Status "AppData (辞書・テーマ)..." -PercentComplete 30
    $appDataResult = Backup-AppDataFolders -BackupBasePath $BackupBasePath -Options $Options
    $totalResults.Success += $appDataResult.Success
    $totalResults.Skipped += $appDataResult.Skipped
    $totalResults.Errors += $appDataResult.Errors

    # クラウドドライブをバックアップ
    Write-Host "  [3/5] クラウドドライブをバックアップ中..." -ForegroundColor Cyan
    Write-Progress -Activity "ユーザーデータバックアップ" -Status "クラウドドライブ (OneDrive等)..." -PercentComplete 50
    $cloudResult = Backup-CloudDriveFolders -BackupBasePath $BackupBasePath -Options $Options
    $totalResults.Success += $cloudResult.Success
    $totalResults.Skipped += $cloudResult.Skipped
    $totalResults.Errors += $cloudResult.Errors

    # ブラウザ終了（オプション）
    if ($Options.ContainsKey('CloseBrowsers') -and $Options['CloseBrowsers']) {
        Write-Host "  [4/5] ブラウザを終了中..." -ForegroundColor Cyan
        Write-Progress -Activity "ユーザーデータバックアップ" -Status "ブラウザを終了中..." -PercentComplete 65
    }

    # ブックマークをバックアップ
    Write-Host "  [5/5] ブラウザデータをバックアップ中..." -ForegroundColor Cyan
    Write-Progress -Activity "ユーザーデータバックアップ" -Status "ブラウザデータ (履歴・お気に入り等)..." -PercentComplete 75
    $bookmarkResult = Backup-BrowserBookmarks -BackupBasePath $BackupBasePath -Options $Options
    $totalResults.Success += $bookmarkResult.Success
    $totalResults.Skipped += $bookmarkResult.Skipped
    $totalResults.Errors += $bookmarkResult.Errors

    # プログレス完了
    Write-Progress -Activity "ユーザーデータバックアップ" -Status "完了" -PercentComplete 100 -Completed
    Write-Host ""
    Write-BackupLog -Message "========================================" -Level 'INFO'
    Write-BackupLog -Message "ユーザーデータバックアップ処理完了" -Level 'INFO'
    Write-BackupLog -Message "成功: $($totalResults.Success), スキップ: $($totalResults.Skipped), エラー: $($totalResults.Errors)" -Level 'INFO'
    Write-BackupLog -Message "========================================" -Level 'INFO'

    return $totalResults
}

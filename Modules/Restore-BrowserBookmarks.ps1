<#
.SYNOPSIS
    Edge/Chromeのブックマークを復元するモジュール

.DESCRIPTION
    - Microsoft Edgeのブックマーク（Bookmarks）を復元
    - Google Chromeのブックマーク（Bookmarks）を復元
    - 既存のブックマークはバックアップ後にマージ可能
    - ブラウザが起動中の場合は警告

.NOTES
    PowerShell 5.1 互換
    ブックマークファイルはJSON形式
#>

#===============================================================================
# ブラウザ設定パス定義
#===============================================================================
$Script:BrowserPaths = @{
    Edge = @{
        Name = "Microsoft Edge"
        ProcessName = "msedge"
        RelativePath = "AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks"
        BackupSuffix = ".backup"
    }
    Chrome = @{
        Name = "Google Chrome"
        ProcessName = "chrome"
        RelativePath = "AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
        BackupSuffix = ".backup"
    }
}

#===============================================================================
# 関数: Write-BookmarkLog
# 説明: ブックマーク復元のログを出力
#===============================================================================
function Write-BookmarkLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'SKIP')]
        [string]$Level = 'INFO'
    )

    $logPath = "C:\AutoSetup\Logs\Restore.log"
    $logDir = Split-Path -Path $logPath -Parent

    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [Bookmark] $Message"

    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8

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
# 関数: Test-BrowserRunning
# 説明: 指定したブラウザが起動中かチェック
#===============================================================================
function Test-BrowserRunning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    return ($null -ne $process)
}

#===============================================================================
# 関数: Backup-ExistingBookmarks
# 説明: 既存のブックマークファイルをバックアップ
#===============================================================================
function Backup-ExistingBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookmarkPath
    )

    if (Test-Path -Path $BookmarkPath) {
        $backupPath = "$BookmarkPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        try {
            Copy-Item -Path $BookmarkPath -Destination $backupPath -Force
            Write-BookmarkLog -Message "既存ブックマークをバックアップ: $backupPath" -Level 'INFO'
            return $backupPath
        }
        catch {
            Write-BookmarkLog -Message "バックアップ失敗: $_" -Level 'ERROR'
            return $null
        }
    }
    return $null
}

#===============================================================================
# 関数: Restore-EdgeBookmarks
# 説明: Microsoft Edgeのブックマークを復元
#===============================================================================
function Restore-EdgeBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUserPath
    )

    $browserInfo = $Script:BrowserPaths.Edge
    Write-BookmarkLog -Message "=== $($browserInfo.Name) ブックマーク復元開始 ===" -Level 'INFO'

    # ソースパスの構築
    $sourceBookmarkPath = Join-Path -Path $SourceUserPath -ChildPath $browserInfo.RelativePath

    # ソースファイル存在チェック
    if (-not (Test-Path -Path $sourceBookmarkPath)) {
        Write-BookmarkLog -Message "Edgeブックマークが見つかりません: $sourceBookmarkPath" -Level 'SKIP'
        return @{ Success = $false; Skipped = $true; Error = $false }
    }

    # ブラウザ起動チェック
    if (Test-BrowserRunning -ProcessName $browserInfo.ProcessName) {
        Write-BookmarkLog -Message "警告: Edgeが起動中です。復元前にEdgeを閉じることを推奨します" -Level 'WARNING'
    }

    # 宛先パスの構築
    $destBookmarkPath = Join-Path -Path $env:USERPROFILE -ChildPath $browserInfo.RelativePath
    $destDir = Split-Path -Path $destBookmarkPath -Parent

    # 宛先ディレクトリ作成
    if (-not (Test-Path -Path $destDir)) {
        try {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            Write-BookmarkLog -Message "宛先ディレクトリ作成: $destDir" -Level 'INFO'
        }
        catch {
            Write-BookmarkLog -Message "ディレクトリ作成失敗: $_" -Level 'ERROR'
            return @{ Success = $false; Skipped = $false; Error = $true }
        }
    }

    # 既存ブックマークのバックアップ
    Backup-ExistingBookmarks -BookmarkPath $destBookmarkPath

    # ブックマークファイルをコピー
    try {
        Copy-Item -Path $sourceBookmarkPath -Destination $destBookmarkPath -Force
        Write-BookmarkLog -Message "Edgeブックマーク復元完了: $destBookmarkPath" -Level 'SUCCESS'
        return @{ Success = $true; Skipped = $false; Error = $false }
    }
    catch {
        Write-BookmarkLog -Message "Edgeブックマーク復元失敗: $_" -Level 'ERROR'
        return @{ Success = $false; Skipped = $false; Error = $true }
    }
}

#===============================================================================
# 関数: Restore-ChromeBookmarks
# 説明: Google Chromeのブックマークを復元
#===============================================================================
function Restore-ChromeBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUserPath
    )

    $browserInfo = $Script:BrowserPaths.Chrome
    Write-BookmarkLog -Message "=== $($browserInfo.Name) ブックマーク復元開始 ===" -Level 'INFO'

    # ソースパスの構築
    $sourceBookmarkPath = Join-Path -Path $SourceUserPath -ChildPath $browserInfo.RelativePath

    # ソースファイル存在チェック
    if (-not (Test-Path -Path $sourceBookmarkPath)) {
        Write-BookmarkLog -Message "Chromeブックマークが見つかりません: $sourceBookmarkPath" -Level 'SKIP'
        return @{ Success = $false; Skipped = $true; Error = $false }
    }

    # ブラウザ起動チェック
    if (Test-BrowserRunning -ProcessName $browserInfo.ProcessName) {
        Write-BookmarkLog -Message "警告: Chromeが起動中です。復元前にChromeを閉じることを推奨します" -Level 'WARNING'
    }

    # 宛先パスの構築
    $destBookmarkPath = Join-Path -Path $env:USERPROFILE -ChildPath $browserInfo.RelativePath
    $destDir = Split-Path -Path $destBookmarkPath -Parent

    # 宛先ディレクトリ作成
    if (-not (Test-Path -Path $destDir)) {
        try {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            Write-BookmarkLog -Message "宛先ディレクトリ作成: $destDir" -Level 'INFO'
        }
        catch {
            Write-BookmarkLog -Message "ディレクトリ作成失敗: $_" -Level 'ERROR'
            return @{ Success = $false; Skipped = $false; Error = $true }
        }
    }

    # 既存ブックマークのバックアップ
    Backup-ExistingBookmarks -BookmarkPath $destBookmarkPath

    # ブックマークファイルをコピー
    try {
        Copy-Item -Path $sourceBookmarkPath -Destination $destBookmarkPath -Force
        Write-BookmarkLog -Message "Chromeブックマーク復元完了: $destBookmarkPath" -Level 'SUCCESS'
        return @{ Success = $true; Skipped = $false; Error = $false }
    }
    catch {
        Write-BookmarkLog -Message "Chromeブックマーク復元失敗: $_" -Level 'ERROR'
        return @{ Success = $false; Skipped = $false; Error = $true }
    }
}

#===============================================================================
# 関数: Restore-AllBrowserBookmarks
# 説明: すべてのブラウザのブックマークを復元（メイン関数）
#===============================================================================
function Restore-AllBrowserBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Array]$SelectedUsers,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $totalResults = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    # ブックマーク復元オプションチェック
    if ($Options.ContainsKey('RestoreBookmarks') -and -not $Options['RestoreBookmarks']) {
        Write-BookmarkLog -Message "ブックマーク復元がオプションでスキップされました" -Level 'SKIP'
        return $totalResults
    }

    Write-BookmarkLog -Message "========================================" -Level 'INFO'
    Write-BookmarkLog -Message "ブラウザブックマーク復元処理開始" -Level 'INFO'
    Write-BookmarkLog -Message "========================================" -Level 'INFO'

    foreach ($user in $SelectedUsers) {
        Write-BookmarkLog -Message "" -Level 'INFO'
        Write-BookmarkLog -Message "--- ユーザー: $($user.UserName) のブックマーク復元 ---" -Level 'INFO'

        # Edge復元
        $edgeResult = Restore-EdgeBookmarks -SourceUserPath $user.UserFullPath
        if ($edgeResult.Success) { $totalResults.Success++ }
        elseif ($edgeResult.Skipped) { $totalResults.Skipped++ }
        else { $totalResults.Errors++ }

        # Chrome復元
        $chromeResult = Restore-ChromeBookmarks -SourceUserPath $user.UserFullPath
        if ($chromeResult.Success) { $totalResults.Success++ }
        elseif ($chromeResult.Skipped) { $totalResults.Skipped++ }
        else { $totalResults.Errors++ }
    }

    Write-BookmarkLog -Message "" -Level 'INFO'
    Write-BookmarkLog -Message "========================================" -Level 'INFO'
    Write-BookmarkLog -Message "ブックマーク復元完了" -Level 'INFO'
    Write-BookmarkLog -Message "成功: $($totalResults.Success), スキップ: $($totalResults.Skipped), エラー: $($totalResults.Errors)" -Level 'INFO'
    Write-BookmarkLog -Message "========================================" -Level 'INFO'

    return $totalResults
}

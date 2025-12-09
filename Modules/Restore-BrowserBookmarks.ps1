<#
.SYNOPSIS
    Edge/Chromeのブラウザデータを復元するモジュール

.DESCRIPTION
    - お気に入り（Bookmarks）を復元
    - 閲覧履歴（History）を復元
    - オートフィル（Web Data）を復元
    - 設定（Preferences）を復元
    - 既存データはバックアップ後に上書き
    - ブラウザが起動中の場合は警告

.NOTES
    PowerShell 5.1 互換
#>

#===============================================================================
# ブラウザデータ定義（お気に入り、履歴、オートフィル、設定）
#===============================================================================
$Script:BrowserDataItems = @(
    # Microsoft Edge
    @{
        Name        = "Edge - お気に入り"
        Browser     = "Edge"
        ProcessName = "msedge"
        RelativePath = "AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks"
    },
    @{
        Name        = "Edge - 閲覧履歴"
        Browser     = "Edge"
        ProcessName = "msedge"
        RelativePath = "AppData\Local\Microsoft\Edge\User Data\Default\History"
    },
    @{
        Name        = "Edge - オートフィル"
        Browser     = "Edge"
        ProcessName = "msedge"
        RelativePath = "AppData\Local\Microsoft\Edge\User Data\Default\Web Data"
    },
    @{
        Name        = "Edge - 設定"
        Browser     = "Edge"
        ProcessName = "msedge"
        RelativePath = "AppData\Local\Microsoft\Edge\User Data\Default\Preferences"
    },
    # Google Chrome
    @{
        Name        = "Chrome - お気に入り"
        Browser     = "Chrome"
        ProcessName = "chrome"
        RelativePath = "AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
    },
    @{
        Name        = "Chrome - 閲覧履歴"
        Browser     = "Chrome"
        ProcessName = "chrome"
        RelativePath = "AppData\Local\Google\Chrome\User Data\Default\History"
    },
    @{
        Name        = "Chrome - オートフィル"
        Browser     = "Chrome"
        ProcessName = "chrome"
        RelativePath = "AppData\Local\Google\Chrome\User Data\Default\Web Data"
    },
    @{
        Name        = "Chrome - 設定"
        Browser     = "Chrome"
        ProcessName = "chrome"
        RelativePath = "AppData\Local\Google\Chrome\User Data\Default\Preferences"
    }
)

#===============================================================================
# 関数: Write-BrowserLog
# 説明: ブラウザデータ復元のログを出力
#===============================================================================
function Write-BrowserLog {
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
    $logEntry = "[$timestamp] [$Level] [Browser] $Message"

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
# 関数: Backup-ExistingFile
# 説明: 既存のファイルをバックアップ
#===============================================================================
function Backup-ExistingFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (Test-Path -Path $FilePath) {
        $backupPath = "$FilePath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        try {
            Copy-Item -Path $FilePath -Destination $backupPath -Force
            Write-BrowserLog -Message "既存ファイルをバックアップ: $backupPath" -Level 'INFO'
            return $backupPath
        }
        catch {
            Write-BrowserLog -Message "バックアップ失敗: $_" -Level 'WARNING'
            return $null
        }
    }
    return $null
}

#===============================================================================
# 関数: Restore-BrowserDataItem
# 説明: 単一のブラウザデータ項目を復元
#===============================================================================
function Restore-BrowserDataItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUserPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$DataItem
    )

    $itemName = $DataItem.Name

    # ソースパスの構築
    $sourcePath = Join-Path -Path $SourceUserPath -ChildPath $DataItem.RelativePath

    # ソースファイル存在チェック
    if (-not (Test-Path -Path $sourcePath)) {
        Write-BrowserLog -Message "[$itemName] ファイルが見つかりません" -Level 'SKIP'
        return @{ Success = $false; Skipped = $true; Error = $false }
    }

    # ブラウザ起動チェック（警告のみ）
    if (Test-BrowserRunning -ProcessName $DataItem.ProcessName) {
        Write-BrowserLog -Message "[$itemName] 警告: $($DataItem.Browser)が起動中です" -Level 'WARNING'
    }

    # 宛先パスの構築
    $destPath = Join-Path -Path $env:USERPROFILE -ChildPath $DataItem.RelativePath
    $destDir = Split-Path -Path $destPath -Parent

    # 宛先ディレクトリ作成
    if (-not (Test-Path -Path $destDir)) {
        try {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }
        catch {
            Write-BrowserLog -Message "[$itemName] ディレクトリ作成失敗: $_" -Level 'ERROR'
            return @{ Success = $false; Skipped = $false; Error = $true }
        }
    }

    # 既存ファイルのバックアップ
    Backup-ExistingFile -FilePath $destPath | Out-Null

    # ファイルをコピー
    try {
        Copy-Item -Path $sourcePath -Destination $destPath -Force
        Write-BrowserLog -Message "[$itemName] 復元完了" -Level 'SUCCESS'
        return @{ Success = $true; Skipped = $false; Error = $false }
    }
    catch {
        Write-BrowserLog -Message "[$itemName] 復元失敗: $_" -Level 'ERROR'
        return @{ Success = $false; Skipped = $false; Error = $true }
    }
}

#===============================================================================
# 関数: Restore-AllBrowserData
# 説明: すべてのブラウザデータを復元
#===============================================================================
function Restore-AllBrowserData {
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

    # ブラウザデータ復元オプションチェック
    if ($Options.ContainsKey('RestoreBookmarks') -and -not $Options['RestoreBookmarks']) {
        Write-BrowserLog -Message "ブラウザデータ復元がオプションでスキップされました" -Level 'SKIP'
        return $totalResults
    }

    Write-BrowserLog -Message "========================================" -Level 'INFO'
    Write-BrowserLog -Message "ブラウザデータ復元処理開始" -Level 'INFO'
    Write-BrowserLog -Message "（お気に入り、閲覧履歴、オートフィル、設定）" -Level 'INFO'
    Write-BrowserLog -Message "========================================" -Level 'INFO'

    # ブラウザ起動中の警告
    $edgeRunning = Test-BrowserRunning -ProcessName "msedge"
    $chromeRunning = Test-BrowserRunning -ProcessName "chrome"

    if ($edgeRunning -or $chromeRunning) {
        Write-BrowserLog -Message "注意: ブラウザを閉じてから復元することを推奨します" -Level 'WARNING'
        if ($edgeRunning) { Write-BrowserLog -Message "  - Microsoft Edge が起動中" -Level 'WARNING' }
        if ($chromeRunning) { Write-BrowserLog -Message "  - Google Chrome が起動中" -Level 'WARNING' }
    }

    foreach ($user in $SelectedUsers) {
        Write-BrowserLog -Message "--- ユーザー: $($user.UserName) のブラウザデータ復元 ---" -Level 'INFO'

        foreach ($dataItem in $Script:BrowserDataItems) {
            $result = Restore-BrowserDataItem -SourceUserPath $user.UserFullPath -DataItem $dataItem

            if ($result.Success) { $totalResults.Success++ }
            elseif ($result.Skipped) { $totalResults.Skipped++ }
            else { $totalResults.Errors++ }
        }
    }

    Write-BrowserLog -Message "========================================" -Level 'INFO'
    Write-BrowserLog -Message "ブラウザデータ復元完了" -Level 'INFO'
    Write-BrowserLog -Message "成功: $($totalResults.Success), スキップ: $($totalResults.Skipped), エラー: $($totalResults.Errors)" -Level 'INFO'
    Write-BrowserLog -Message "========================================" -Level 'INFO'

    return $totalResults
}

#===============================================================================
# 後方互換性のためのエイリアス
#===============================================================================
function Restore-AllBrowserBookmarks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Array]$SelectedUsers,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    return Restore-AllBrowserData -SelectedUsers $SelectedUsers -Options $Options
}

# 旧関数名のエイリアス（互換性維持）
function Write-BookmarkLog {
    param([string]$Message, [string]$Level = 'INFO')
    Write-BrowserLog -Message $Message -Level $Level
}

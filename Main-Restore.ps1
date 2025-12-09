<#
.SYNOPSIS
    ユーザーデータ復元ツール - メインスクリプト

.DESCRIPTION
    外付けHDDに保存された旧PCのユーザーデータを、
    新しいWindows環境へ安全に復元する自動ツール

    機能:
    - 外付けHDDの自動検出
    - GUIでユーザー選択（複数選択可）
    - Desktop, Documents等の標準フォルダ復元
    - Edge/Chromeブックマーク復元
    - レジストリ設定復元（IME等の安全な設定のみ）

.PARAMETER Silent
    GUIを表示せず、見つかったすべてのユーザーを復元

.PARAMETER LogPath
    ログファイルの出力先（デフォルト: C:\AutoSetup\Logs\Restore.log）

.EXAMPLE
    .\Main-Restore.ps1
    GUIを表示してユーザーを選択し、復元を実行

.EXAMPLE
    .\Main-Restore.ps1 -Silent
    GUIなしで全ユーザーを自動復元

.NOTES
    PowerShell 5.1 互換
    作成日: 2024
    管理者権限推奨（レジストリ復元に必要）
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Silent,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\AutoSetup\Logs\Restore.log"
)

#===============================================================================
# スクリプト設定
#===============================================================================
$ErrorActionPreference = "Continue"
$Script:StartTime = Get-Date
$Script:ScriptRoot = $PSScriptRoot

# ログパスをグローバルに設定
$Script:LogPath = $LogPath

#===============================================================================
# 関数: Write-MainLog
# 説明: メインログ出力
#===============================================================================
function Write-MainLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $logDir = Split-Path -Path $Script:LogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    Add-Content -Path $Script:LogPath -Value $logEntry -Encoding UTF8

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        default   { 'White' }
    }
    Write-Host $logEntry -ForegroundColor $color
}

#===============================================================================
# 関数: Import-RestoreModules
# 説明: 必要なモジュールを読み込み
#===============================================================================
function Import-RestoreModules {
    [CmdletBinding()]
    param()

    Write-MainLog -Message "モジュールを読み込み中..." -Level 'INFO'

    $modulesPath = Join-Path -Path $Script:ScriptRoot -ChildPath "Modules"

    $modules = @(
        "Scan-Backup.ps1",
        "Restore-GUI.ps1",
        "Copy-UserData.ps1",
        "Restore-BrowserBookmarks.ps1",
        "Restore-Registry.ps1"
    )

    foreach ($module in $modules) {
        $modulePath = Join-Path -Path $modulesPath -ChildPath $module
        if (Test-Path -Path $modulePath) {
            try {
                . $modulePath
                Write-MainLog -Message "モジュール読み込み成功: $module" -Level 'SUCCESS'
            }
            catch {
                Write-MainLog -Message "モジュール読み込み失敗: $module - $_" -Level 'ERROR'
                throw "モジュールの読み込みに失敗しました: $module"
            }
        }
        else {
            Write-MainLog -Message "モジュールが見つかりません: $modulePath" -Level 'ERROR'
            throw "モジュールが見つかりません: $modulePath"
        }
    }
}

#===============================================================================
# 関数: Test-AdminPrivilege
# 説明: 管理者権限チェック
#===============================================================================
function Test-AdminPrivilege {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#===============================================================================
# 関数: Show-Banner
# 説明: 開始バナー表示
#===============================================================================
function Show-Banner {
    $banner = @"

 =====================================================
   ユーザーデータ復元ツール v1.0
   User Data Restore Tool for Windows
 =====================================================

   機能:
   - 外付けHDD内のユーザーデータを自動検出
   - Desktop, Documents等のフォルダを復元
   - Edge/Chromeのブックマークを復元
   - IME等のユーザー設定を復元

 =====================================================

"@
    Write-Host $banner -ForegroundColor Cyan
}

#===============================================================================
# 関数: Start-RestoreProcess
# 説明: 復元処理のメインフロー
#===============================================================================
function Start-RestoreProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    # 開始ログ
    Write-MainLog -Message "========================================" -Level 'INFO'
    Write-MainLog -Message "復元ツール開始" -Level 'INFO'
    Write-MainLog -Message "実行ユーザー: $env:USERNAME" -Level 'INFO'
    Write-MainLog -Message "コンピュータ名: $env:COMPUTERNAME" -Level 'INFO'
    Write-MainLog -Message "管理者権限: $(if (Test-AdminPrivilege) { 'あり' } else { 'なし' })" -Level 'INFO'
    Write-MainLog -Message "========================================" -Level 'INFO'

    # 管理者権限警告
    if (-not (Test-AdminPrivilege)) {
        Write-MainLog -Message "警告: 管理者権限なしで実行中。レジストリ復元がスキップされる可能性があります" -Level 'WARNING'
    }

    #---------------------------------------------------------------------------
    # Step 1: バックアップドライブをスキャン
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 1: バックアップドライブをスキャン中..." -Level 'INFO'

    $backupUsers = Scan-AllBackupDrives

    if (-not $backupUsers -or $backupUsers.Count -eq 0) {
        Write-MainLog -Message "復元可能なユーザーが見つかりませんでした" -Level 'ERROR'
        Write-MainLog -Message "外付けHDDが正しく接続されているか確認してください" -Level 'ERROR'

        if (-not $Silent) {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                "復元可能なユーザーが見つかりませんでした。`n`n外付けHDDが正しく接続されているか確認してください。",
                "エラー",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
        return
    }

    Write-MainLog -Message "検出されたユーザー数: $($backupUsers.Count)" -Level 'SUCCESS'

    #---------------------------------------------------------------------------
    # Step 2: ユーザー選択（GUIまたは全選択）
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 2: ユーザー選択..." -Level 'INFO'

    $selectedUsers = @()
    $options = @{}

    if ($Silent) {
        # サイレントモード: 全ユーザーを選択
        Write-MainLog -Message "サイレントモード: すべてのユーザーを復元対象にします" -Level 'INFO'
        $selectedUsers = $backupUsers
        $options = @{
            RestoreDesktop    = $true
            RestoreDocuments  = $true
            RestorePictures   = $true
            RestoreVideos     = $true
            RestoreMusic      = $true
            RestoreDownloads  = $true
            RestoreAppData    = $true
            RestoreBookmarks  = $true
            RestoreRegistry   = $true
            RestoreCloudDrive = $true
        }
    }
    else {
        # GUIモード: ユーザーに選択させる
        Write-MainLog -Message "GUIを表示中..." -Level 'INFO'

        $dialogResult = Show-UserSelectionDialog -BackupUsers $backupUsers

        if (-not $dialogResult.Confirmed) {
            Write-MainLog -Message "ユーザーがキャンセルしました" -Level 'WARNING'
            return
        }

        $selectedUsers = $dialogResult.SelectedUsers
        $options = $dialogResult.Options

        Write-MainLog -Message "選択されたユーザー数: $($selectedUsers.Count)" -Level 'SUCCESS'
    }

    # 選択ユーザーをログに記録
    foreach ($user in $selectedUsers) {
        Write-MainLog -Message "  - $($user.UserName) ($($user.UserFullPath))" -Level 'INFO'
    }

    #---------------------------------------------------------------------------
    # Step 3: 復元確認
    #---------------------------------------------------------------------------
    if (-not $Silent) {
        $confirmMessage = @"
以下の復元を実行します:

選択ユーザー: $($selectedUsers.Count)名
$(($selectedUsers | ForEach-Object { "  - $($_.UserName)" }) -join "`n")

復元先: $env:USERPROFILE

続行しますか?
"@
        $confirmed = Show-ConfirmDialog -Message $confirmMessage -Title "復元確認"

        if (-not $confirmed) {
            Write-MainLog -Message "ユーザーが復元をキャンセルしました" -Level 'WARNING'
            return
        }
    }

    #---------------------------------------------------------------------------
    # Step 4: ユーザーデータをコピー
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 3: ユーザーデータをコピー中..." -Level 'INFO'

    $copyResults = Copy-AllUserData -SelectedUsers $selectedUsers -Options $options

    #---------------------------------------------------------------------------
    # Step 5: ブラウザブックマークを復元
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 4: ブラウザブックマークを復元中..." -Level 'INFO'

    $bookmarkResults = Restore-AllBrowserBookmarks -SelectedUsers $selectedUsers -Options $options

    #---------------------------------------------------------------------------
    # Step 6: レジストリを復元
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 5: レジストリ設定を復元中..." -Level 'INFO'

    $registryResults = Restore-UserRegistry -SelectedUsers $selectedUsers -Options $options

    #---------------------------------------------------------------------------
    # 完了サマリー
    #---------------------------------------------------------------------------
    $totalSuccess = $copyResults.Success + $bookmarkResults.Success + $registryResults.Success
    $totalSkipped = $copyResults.Skipped + $bookmarkResults.Skipped + $registryResults.Skipped
    $totalErrors = $copyResults.Errors + $bookmarkResults.Errors + $registryResults.Errors

    $endTime = Get-Date
    $duration = $endTime - $Script:StartTime

    Write-Host ""
    Write-MainLog -Message "========================================" -Level 'INFO'
    Write-MainLog -Message "復元処理完了" -Level 'SUCCESS'
    Write-MainLog -Message "========================================" -Level 'INFO'
    Write-MainLog -Message "処理時間: $($duration.ToString('hh\:mm\:ss'))" -Level 'INFO'
    Write-Host ""
    Write-MainLog -Message "[サマリー]" -Level 'INFO'
    Write-MainLog -Message "  成功:     $totalSuccess 項目" -Level 'SUCCESS'
    Write-MainLog -Message "  スキップ: $totalSkipped 項目" -Level 'WARNING'
    Write-MainLog -Message "  エラー:   $totalErrors 項目" -Level $(if ($totalErrors -gt 0) { 'ERROR' } else { 'INFO' })
    Write-Host ""
    Write-MainLog -Message "ログファイル: $Script:LogPath" -Level 'INFO'
    Write-MainLog -Message "========================================" -Level 'INFO'

    # 完了ダイアログ
    if (-not $Silent) {
        Show-CompletionDialog -SuccessCount $totalSuccess -SkipCount $totalSkipped -ErrorCount $totalErrors -LogPath $Script:LogPath
    }
}

#===============================================================================
# メイン処理
#===============================================================================
try {
    # バナー表示
    Show-Banner

    # モジュール読み込み
    Import-RestoreModules

    # 復元処理開始
    Start-RestoreProcess -Silent:$Silent
}
catch {
    Write-MainLog -Message "致命的エラー: $_" -Level 'ERROR'
    Write-MainLog -Message "スタックトレース: $($_.ScriptStackTrace)" -Level 'ERROR'

    if (-not $Silent) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "エラーが発生しました:`n`n$_",
            "エラー",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }

    exit 1
}

Write-Host "`n処理が完了しました。何かキーを押すと終了します..." -ForegroundColor Green
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

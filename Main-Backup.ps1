<#
.SYNOPSIS
    ユーザーデータ バックアップツール - メインスクリプト

.DESCRIPTION
    現在のPCのユーザーデータを外付けHDDにバックアップする自動ツール

    機能:
    - 外付けHDDの自動検出
    - GUIでバックアップ先・対象を選択
    - Desktop, Documents等の標準フォルダをバックアップ
    - Edge/Chromeブックマークをバックアップ
    - レジストリ設定をエクスポート

.PARAMETER Silent
    GUIを表示せず、最初に見つかったドライブに自動バックアップ

.PARAMETER LogPath
    ログファイルの出力先（デフォルト: C:\AutoSetup\Logs\Backup.log）

.EXAMPLE
    .\Main-Backup.ps1
    GUIを表示してバックアップ先を選択し、バックアップを実行

.EXAMPLE
    .\Main-Backup.ps1 -Silent
    GUIなしで自動バックアップ

.NOTES
    PowerShell 5.1 互換
    作成日: 2024
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Silent,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\AutoSetup\Logs\Backup.log"
)

#===============================================================================
# スクリプト設定
#===============================================================================
$ErrorActionPreference = "Continue"
$Script:StartTime = Get-Date
$Script:ScriptRoot = $PSScriptRoot

# ログパスをグローバルに設定
$Script:LogPath = $LogPath

# 進行状況スピナー用
$Script:SpinnerRunning = $false
$Script:SpinnerJob = $null

#===============================================================================
# 関数: Start-ProgressSpinner
# 説明: 進行状況スピナーを開始
#===============================================================================
function Start-ProgressSpinner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Message = "処理中"
    )

    $Script:SpinnerRunning = $true
    $spinChars = @('|', '/', '-', '\')
    $i = 0

    # バックグラウンドで回転表示
    $Script:SpinnerJob = Start-Job -ScriptBlock {
        param($msg, $chars)
        $i = 0
        while ($true) {
            $char = $chars[$i % 4]
            Write-Host "`r  $char $msg $char  " -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 200
            $i++
        }
    } -ArgumentList $Message, $spinChars
}

#===============================================================================
# 関数: Stop-ProgressSpinner
# 説明: 進行状況スピナーを停止
#===============================================================================
function Stop-ProgressSpinner {
    [CmdletBinding()]
    param()

    if ($Script:SpinnerJob) {
        Stop-Job -Job $Script:SpinnerJob -ErrorAction SilentlyContinue
        Remove-Job -Job $Script:SpinnerJob -Force -ErrorAction SilentlyContinue
        $Script:SpinnerJob = $null
    }
    Write-Host "`r                                        `r" -NoNewline
}

#===============================================================================
# 関数: Show-ProgressActivity
# 説明: 処理中のアクティビティを表示（シンプル版）
#===============================================================================
function Show-ProgressActivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Activity,

        [Parameter(Mandatory = $false)]
        [int]$Current = 0,

        [Parameter(Mandatory = $false)]
        [int]$Total = 0
    )

    $progressText = if ($Total -gt 0) {
        "[$Current/$Total] $Activity"
    } else {
        $Activity
    }

    # プログレスバー表示
    Write-Progress -Activity "バックアップ処理中" -Status $progressText -PercentComplete (($Current / [Math]::Max($Total, 1)) * 100)
}

#===============================================================================
# 関数: Play-CompletionSound
# 説明: 完了音を鳴らす
#===============================================================================
function Play-CompletionSound {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Success', 'Error', 'Warning')]
        [string]$Type = 'Success'
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

        switch ($Type) {
            'Success' {
                # 成功音（3回ビープ）
                [Console]::Beep(800, 200)
                Start-Sleep -Milliseconds 100
                [Console]::Beep(1000, 200)
                Start-Sleep -Milliseconds 100
                [Console]::Beep(1200, 300)
            }
            'Error' {
                # エラー音
                [Console]::Beep(300, 500)
                [System.Media.SystemSounds]::Hand.Play()
            }
            'Warning' {
                # 警告音
                [Console]::Beep(600, 300)
                [System.Media.SystemSounds]::Exclamation.Play()
            }
        }
    }
    catch {
        # 音が鳴らなくても続行
    }
}

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
# モジュール読み込み（スクリプトレベルで実行）
#===============================================================================
$Script:ModulesPath = Join-Path -Path $Script:ScriptRoot -ChildPath "Modules"
$Script:ModuleList = @(
    "Backup-GUI.ps1",
    "Backup-UserData.ps1",
    "Backup-Registry.ps1",
    "Backup-WiFi.ps1"
)

function Import-BackupModules {
    [CmdletBinding()]
    param()

    Write-MainLog -Message "モジュールを読み込み中..." -Level 'INFO'

    foreach ($module in $Script:ModuleList) {
        $modulePath = Join-Path -Path $Script:ModulesPath -ChildPath $module
        if (Test-Path -Path $modulePath) {
            Write-MainLog -Message "モジュール読み込み成功: $module" -Level 'SUCCESS'
        }
        else {
            Write-MainLog -Message "モジュールが見つかりません: $modulePath" -Level 'ERROR'
            throw "モジュールが見つかりません: $modulePath"
        }
    }
}

# スクリプトレベルでモジュールを読み込み（関数スコープ外）
foreach ($module in $Script:ModuleList) {
    $modulePath = Join-Path -Path $Script:ModulesPath -ChildPath $module
    if (Test-Path -Path $modulePath) {
        . $modulePath
    }
}

#===============================================================================
# 関数: Show-Banner
# 説明: 開始バナー表示
#===============================================================================
function Show-Banner {
    $banner = @"

 =====================================================
   ユーザーデータ バックアップツール v1.0
   User Data Backup Tool for Windows
 =====================================================

   機能:
   - ユーザーデータを外付けHDDにバックアップ
   - Desktop, Documents等のフォルダを保存
   - Edge/Chromeのブックマークを保存
   - IME等のユーザー設定を保存

 =====================================================

"@
    Write-Host $banner -ForegroundColor Cyan
}

#===============================================================================
# 関数: Start-BackupProcess
# 説明: バックアップ処理のメインフロー
#===============================================================================
function Start-BackupProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    # 開始ログ
    Write-MainLog -Message "========================================" -Level 'INFO'
    Write-MainLog -Message "バックアップツール開始" -Level 'INFO'
    Write-MainLog -Message "実行ユーザー: $env:USERNAME" -Level 'INFO'
    Write-MainLog -Message "コンピュータ名: $env:COMPUTERNAME" -Level 'INFO'
    Write-MainLog -Message "========================================" -Level 'INFO'

    #---------------------------------------------------------------------------
    # Step 1: バックアップ設定（GUIまたは自動）
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 1: バックアップ設定..." -Level 'INFO'

    $targetDrive = $null
    $backupFolderName = "Backup_$env:COMPUTERNAME`_$(Get-Date -Format 'yyyyMMdd')"
    $options = @{}

    if ($Silent) {
        # サイレントモード: 最初のドライブを自動選択
        Write-MainLog -Message "サイレントモード: ドライブを自動検出中..." -Level 'INFO'

        $drives = Get-AvailableDrives
        if (-not $drives -or $drives.Count -eq 0) {
            Write-MainLog -Message "外付けドライブが見つかりません" -Level 'ERROR'
            return
        }

        $targetDrive = $drives[0]
        Write-MainLog -Message "選択されたドライブ: $($targetDrive.DriveLetter) - $($targetDrive.VolumeName)" -Level 'INFO'

        $options = @{
            BackupDesktop     = $true
            BackupDocuments   = $true
            BackupPictures    = $true
            BackupVideos      = $true
            BackupMusic       = $true
            BackupDownloads   = $true
            BackupAppData     = $true
            BackupBookmarks   = $true
            BackupRegistry    = $true
            BackupCloudDrive  = $true
            BackupWiFi        = $true
            CloseBrowsers     = $true
        }
    }
    else {
        # GUIモード: ユーザーに選択させる
        Write-MainLog -Message "GUIを表示中..." -Level 'INFO'

        $dialogResult = Show-BackupDialog

        if (-not $dialogResult.Confirmed) {
            Write-MainLog -Message "ユーザーがキャンセルしました" -Level 'WARNING'
            return
        }

        $targetDrive = $dialogResult.TargetDrive
        $backupFolderName = $dialogResult.BackupFolderName
        $options = $dialogResult.Options

        Write-MainLog -Message "選択されたドライブ: $($targetDrive.DriveLetter) - $($targetDrive.VolumeName)" -Level 'SUCCESS'
    }

    # バックアップ先パスを構築
    $backupBasePath = Join-Path -Path $targetDrive.DriveLetter -ChildPath $backupFolderName
    $backupUserPath = Join-Path -Path $backupBasePath -ChildPath "Users\$env:USERNAME"

    # 既存バックアップかどうか確認
    $isResume = Test-Path -Path $backupBasePath
    $backupMode = if ($isResume) { "レジューム（差分バックアップ）" } else { "新規バックアップ" }

    Write-MainLog -Message "バックアップ先: $backupUserPath" -Level 'INFO'
    Write-MainLog -Message "モード: $backupMode" -Level 'INFO'

    #---------------------------------------------------------------------------
    # Step 2: バックアップ確認
    #---------------------------------------------------------------------------
    if (-not $Silent) {
        if ($isResume) {
            $confirmMessage = @"
【レジューム（続き）モード】

既存のバックアップフォルダが見つかりました。
変更・追加されたファイルのみバックアップします。

バックアップ元: $env:USERPROFILE
バックアップ先: $backupUserPath

空き容量: $($targetDrive.FreeSpaceGB) GB

※ 同じファイルはスキップされます（高速）
※ 中断しても再実行で続きから再開できます

続行しますか?
"@
            $dialogTitle = "レジューム確認"
        }
        else {
            $confirmMessage = @"
【新規バックアップモード】

新しいバックアップフォルダを作成します。

バックアップ元: $env:USERPROFILE
バックアップ先: $backupUserPath

空き容量: $($targetDrive.FreeSpaceGB) GB

続行しますか?
"@
            $dialogTitle = "新規バックアップ確認"
        }

        $confirmed = Show-BackupConfirmDialog -Message $confirmMessage -Title $dialogTitle

        if (-not $confirmed) {
            Write-MainLog -Message "ユーザーがバックアップをキャンセルしました" -Level 'WARNING'
            return
        }
    }

    #---------------------------------------------------------------------------
    # Step 3: ユーザーデータをバックアップ
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 2: ユーザーデータをバックアップ中..." -Level 'INFO'
    Write-Progress -Activity "バックアップ処理中" -Status "ユーザーデータをバックアップ中..." -PercentComplete 30

    $dataResults = Backup-AllUserData -BackupBasePath $backupUserPath -Options $options

    #---------------------------------------------------------------------------
    # Step 4: レジストリをバックアップ
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 3: レジストリ設定をバックアップ中..." -Level 'INFO'
    Write-Progress -Activity "バックアップ処理中" -Status "レジストリをバックアップ中..." -PercentComplete 60

    $registryResults = Backup-UserRegistry -BackupBasePath $backupUserPath -Options $options

    #---------------------------------------------------------------------------
    # Step 5: WiFi設定をバックアップ
    #---------------------------------------------------------------------------
    Write-Host ""
    Write-MainLog -Message "Step 4: WiFi設定をバックアップ中..." -Level 'INFO'
    Write-Progress -Activity "バックアップ処理中" -Status "WiFi設定をバックアップ中..." -PercentComplete 85

    $wifiResults = Backup-WiFiProfiles -BackupPath $backupBasePath -Options $options

    # プログレス完了
    Write-Progress -Activity "バックアップ処理中" -Status "完了" -PercentComplete 100 -Completed

    #---------------------------------------------------------------------------
    # 完了サマリー
    #---------------------------------------------------------------------------
    $totalSuccess = $dataResults.Success + $registryResults.Success + $wifiResults.Success
    $totalSkipped = $dataResults.Skipped + $registryResults.Skipped + $wifiResults.Skipped
    $totalErrors = $dataResults.Errors + $registryResults.Errors + $wifiResults.Errors

    $endTime = Get-Date
    $duration = $endTime - $Script:StartTime

    Write-Host ""
    Write-MainLog -Message "========================================" -Level 'INFO'
    Write-MainLog -Message "バックアップ処理完了" -Level 'SUCCESS'
    Write-MainLog -Message "========================================" -Level 'INFO'
    Write-MainLog -Message "処理時間: $($duration.ToString('hh\:mm\:ss'))" -Level 'INFO'
    Write-Host ""
    Write-MainLog -Message "[サマリー]" -Level 'INFO'
    Write-MainLog -Message "  成功:     $totalSuccess 項目" -Level 'SUCCESS'
    Write-MainLog -Message "  スキップ: $totalSkipped 項目" -Level 'WARNING'
    Write-MainLog -Message "  エラー:   $totalErrors 項目" -Level $(if ($totalErrors -gt 0) { 'ERROR' } else { 'INFO' })
    Write-Host ""
    Write-MainLog -Message "バックアップ先: $backupUserPath" -Level 'INFO'
    Write-MainLog -Message "ログファイル: $Script:LogPath" -Level 'INFO'
    Write-MainLog -Message "========================================" -Level 'INFO'

    # 完了音を鳴らす
    if ($totalErrors -gt 0) {
        Play-CompletionSound -Type 'Warning'
    }
    else {
        Play-CompletionSound -Type 'Success'
    }

    # 完了ダイアログ
    if (-not $Silent) {
        Show-BackupCompletionDialog `
            -SuccessCount $totalSuccess `
            -SkipCount $totalSkipped `
            -ErrorCount $totalErrors `
            -BackupPath $backupUserPath `
            -LogPath $Script:LogPath
    }
}

#===============================================================================
# メイン処理
#===============================================================================
try {
    # バナー表示
    Show-Banner

    # モジュール読み込み
    Import-BackupModules

    # バックアップ処理開始
    Start-BackupProcess -Silent:$Silent
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

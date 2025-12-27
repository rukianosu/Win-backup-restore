<#
.SYNOPSIS
    電源管理モジュール - バックアップ/復元中のスリープ防止

.DESCRIPTION
    - AC接続時のディスプレイOFF時間とスリープ時間を記録
    - 処理中は電源設定を無効化
    - 完了後に元の設定を復元

.NOTES
    PowerShell 5.1 互換
#>

# 保存された電源設定
$Script:OriginalPowerSettings = @{
    DisplayTimeout = $null
    SleepTimeout = $null
    Saved = $false
}

#===============================================================================
# 関数: Write-PowerLog
# 説明: 電源管理のログを出力
#===============================================================================
function Write-PowerLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [Power] $Message"

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        default   { 'White' }
    }
    Write-Host $logEntry -ForegroundColor $color
}

#===============================================================================
# 関数: Get-CurrentPowerSettings
# 説明: 現在の電源設定を取得（AC接続時）
#===============================================================================
function Get-CurrentPowerSettings {
    [CmdletBinding()]
    param()

    try {
        # powercfg で現在の設定を取得
        # ディスプレイOFF時間（AC）
        $displayOutput = powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 2>&1
        $displayMatch = $displayOutput | Select-String -Pattern "現在の AC 電源設定インデックス: 0x([0-9a-fA-F]+)" -ErrorAction SilentlyContinue
        if (-not $displayMatch) {
            # 英語OS対応
            $displayMatch = $displayOutput | Select-String -Pattern "Current AC Power Setting Index: 0x([0-9a-fA-F]+)" -ErrorAction SilentlyContinue
        }

        $displayTimeout = 0
        if ($displayMatch) {
            $displayTimeout = [Convert]::ToInt32($displayMatch.Matches[0].Groups[1].Value, 16)
        }

        # スリープ時間（AC）
        $sleepOutput = powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>&1
        $sleepMatch = $sleepOutput | Select-String -Pattern "現在の AC 電源設定インデックス: 0x([0-9a-fA-F]+)" -ErrorAction SilentlyContinue
        if (-not $sleepMatch) {
            # 英語OS対応
            $sleepMatch = $sleepOutput | Select-String -Pattern "Current AC Power Setting Index: 0x([0-9a-fA-F]+)" -ErrorAction SilentlyContinue
        }

        $sleepTimeout = 0
        if ($sleepMatch) {
            $sleepTimeout = [Convert]::ToInt32($sleepMatch.Matches[0].Groups[1].Value, 16)
        }

        return @{
            DisplayTimeout = $displayTimeout  # 秒単位
            SleepTimeout = $sleepTimeout      # 秒単位
        }
    }
    catch {
        Write-PowerLog -Message "電源設定の取得に失敗: $_" -Level 'WARNING'
        return @{
            DisplayTimeout = 0
            SleepTimeout = 0
        }
    }
}

#===============================================================================
# 関数: Disable-PowerSaving
# 説明: 電源設定を保存してスリープを無効化
#===============================================================================
function Disable-PowerSaving {
    [CmdletBinding()]
    param()

    Write-PowerLog -Message "電源設定を一時的に変更します..." -Level 'INFO'

    try {
        # 現在の設定を保存
        $currentSettings = Get-CurrentPowerSettings
        $Script:OriginalPowerSettings.DisplayTimeout = $currentSettings.DisplayTimeout
        $Script:OriginalPowerSettings.SleepTimeout = $currentSettings.SleepTimeout
        $Script:OriginalPowerSettings.Saved = $true

        $displayMin = [Math]::Floor($currentSettings.DisplayTimeout / 60)
        $sleepMin = [Math]::Floor($currentSettings.SleepTimeout / 60)

        Write-PowerLog -Message "現在の設定を記録: ディスプレイOFF=$displayMin 分, スリープ=$sleepMin 分" -Level 'INFO'

        # ディスプレイOFFを無効化（0 = なし）
        $null = powercfg /change monitor-timeout-ac 0

        # スリープを無効化（0 = なし）
        $null = powercfg /change standby-timeout-ac 0

        Write-PowerLog -Message "スリープとディスプレイOFFを無効化しました" -Level 'SUCCESS'

        return $true
    }
    catch {
        Write-PowerLog -Message "電源設定の変更に失敗: $_" -Level 'ERROR'
        return $false
    }
}

#===============================================================================
# 関数: Restore-PowerSaving
# 説明: 保存した電源設定を復元
#===============================================================================
function Restore-PowerSaving {
    [CmdletBinding()]
    param()

    if (-not $Script:OriginalPowerSettings.Saved) {
        Write-PowerLog -Message "復元する電源設定がありません" -Level 'WARNING'
        return $false
    }

    Write-PowerLog -Message "電源設定を元に戻しています..." -Level 'INFO'

    try {
        # ディスプレイOFFを復元（分単位に変換）
        $displayMin = [Math]::Ceiling($Script:OriginalPowerSettings.DisplayTimeout / 60)
        $null = powercfg /change monitor-timeout-ac $displayMin

        # スリープを復元（分単位に変換）
        $sleepMin = [Math]::Ceiling($Script:OriginalPowerSettings.SleepTimeout / 60)
        $null = powercfg /change standby-timeout-ac $sleepMin

        Write-PowerLog -Message "電源設定を復元: ディスプレイOFF=$displayMin 分, スリープ=$sleepMin 分" -Level 'SUCCESS'

        $Script:OriginalPowerSettings.Saved = $false

        return $true
    }
    catch {
        Write-PowerLog -Message "電源設定の復元に失敗: $_" -Level 'ERROR'
        return $false
    }
}

#===============================================================================
# 関数: Invoke-WithPowerManagement
# 説明: 電源管理付きでスクリプトブロックを実行
#===============================================================================
function Invoke-WithPowerManagement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock
    )

    try {
        # 電源設定を無効化
        Disable-PowerSaving | Out-Null

        # 処理を実行
        & $ScriptBlock
    }
    finally {
        # 必ず電源設定を復元
        Restore-PowerSaving | Out-Null
    }
}

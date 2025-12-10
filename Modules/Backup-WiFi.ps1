<#
.SYNOPSIS
    WiFiプロファイルをバックアップするモジュール

.DESCRIPTION
    - netsh wlan export profile でWiFi設定をXMLにエクスポート
    - パスワードも含めてバックアップ（管理者権限必要）
    - 家庭用WiFi（WPA2/WPA3-Personal）はほぼ100%成功
    - 企業WiFi（802.1X）は証明書が別途必要なため復元時に注意

.NOTES
    PowerShell 5.1 互換
    管理者権限推奨（パスワード含める場合は必須）
#>

#===============================================================================
# 関数: Write-WiFiLog
# 説明: WiFiバックアップのログを出力
#===============================================================================
function Write-WiFiLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'SKIP')]
        [string]$Level = 'INFO'
    )

    $logPath = "C:\AutoSetup\Logs\Backup.log"
    $logDir = Split-Path -Path $logPath -Parent

    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [WiFi] $Message"

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
# 関数: Test-IsAdministrator
# 説明: 管理者権限で実行されているかチェック
#===============================================================================
function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#===============================================================================
# 関数: Get-WiFiProfiles
# 説明: 保存されているWiFiプロファイル一覧を取得
#===============================================================================
function Get-WiFiProfiles {
    [CmdletBinding()]
    param()

    try {
        $output = netsh wlan show profiles 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-WiFiLog -Message "WiFiプロファイルの取得に失敗しました" -Level 'ERROR'
            return @()
        }

        # プロファイル名を抽出（日本語/英語両対応）
        $profiles = @()
        foreach ($line in $output) {
            # "All User Profile" または "すべてのユーザー プロファイル" の行を探す
            if ($line -match "^\s*(All User Profile|すべてのユーザー プロファイル)\s*:\s*(.+)$") {
                $profileName = $matches[2].Trim()
                if ($profileName) {
                    $profiles += $profileName
                }
            }
        }

        return $profiles
    }
    catch {
        Write-WiFiLog -Message "WiFiプロファイル取得エラー: $_" -Level 'ERROR'
        return @()
    }
}

#===============================================================================
# 関数: Backup-WiFiProfiles
# 説明: WiFiプロファイルをXMLファイルにエクスポート
#===============================================================================
function Backup-WiFiProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
        ProfileNames = @()
    }

    # WiFiバックアップオプションチェック
    if ($Options.ContainsKey('BackupWiFi') -and -not $Options['BackupWiFi']) {
        Write-WiFiLog -Message "WiFiバックアップがオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    Write-WiFiLog -Message "========================================" -Level 'INFO'
    Write-WiFiLog -Message "WiFiプロファイル バックアップ開始" -Level 'INFO'
    Write-WiFiLog -Message "========================================" -Level 'INFO'

    # WiFiサービスチェック
    $wlanService = Get-Service -Name "WlanSvc" -ErrorAction SilentlyContinue
    if (-not $wlanService -or $wlanService.Status -ne 'Running') {
        Write-WiFiLog -Message "WiFiサービスが利用できません（有線接続のみの環境）" -Level 'SKIP'
        return $results
    }

    # 管理者権限チェック
    $isAdmin = Test-IsAdministrator
    if (-not $isAdmin) {
        Write-WiFiLog -Message "警告: 管理者権限がないため、パスワードなしでエクスポートします" -Level 'WARNING'
    }

    # WiFiバックアップフォルダを作成
    $wifiBackupPath = Join-Path -Path $BackupPath -ChildPath "WiFi"
    if (-not (Test-Path -Path $wifiBackupPath)) {
        New-Item -Path $wifiBackupPath -ItemType Directory -Force | Out-Null
    }

    # プロファイル一覧を取得
    $profiles = Get-WiFiProfiles

    if ($profiles.Count -eq 0) {
        Write-WiFiLog -Message "保存されているWiFiプロファイルがありません" -Level 'SKIP'
        return $results
    }

    Write-WiFiLog -Message "検出されたWiFiプロファイル数: $($profiles.Count)" -Level 'INFO'

    # 各プロファイルをエクスポート
    foreach ($profileName in $profiles) {
        Write-WiFiLog -Message "エクスポート中: $profileName" -Level 'INFO'

        try {
            # パスワード含めてエクスポート（管理者権限がある場合）
            if ($isAdmin) {
                $exportResult = netsh wlan export profile name="$profileName" folder="$wifiBackupPath" key=clear 2>&1
            }
            else {
                $exportResult = netsh wlan export profile name="$profileName" folder="$wifiBackupPath" 2>&1
            }

            if ($LASTEXITCODE -eq 0) {
                Write-WiFiLog -Message "  成功: $profileName" -Level 'SUCCESS'
                $results.Success++
                $results.ProfileNames += $profileName
            }
            else {
                Write-WiFiLog -Message "  失敗: $profileName - $exportResult" -Level 'ERROR'
                $results.Errors++
            }
        }
        catch {
            Write-WiFiLog -Message "  エラー: $profileName - $_" -Level 'ERROR'
            $results.Errors++
        }
    }

    Write-WiFiLog -Message "========================================" -Level 'INFO'
    Write-WiFiLog -Message "WiFiバックアップ完了" -Level 'INFO'
    Write-WiFiLog -Message "成功: $($results.Success), エラー: $($results.Errors)" -Level 'INFO'
    if ($results.Success -gt 0) {
        Write-WiFiLog -Message "保存先: $wifiBackupPath" -Level 'INFO'
    }
    Write-WiFiLog -Message "========================================" -Level 'INFO'

    return $results
}

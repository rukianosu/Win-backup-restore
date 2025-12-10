<#
.SYNOPSIS
    WiFiプロファイルをバックアップするモジュール

.DESCRIPTION
    - netsh wlan export profile でWiFi設定をXMLにエクスポート
    - パスワードも含めてバックアップ（管理者権限必要）

.NOTES
    PowerShell 5.1 互換
    管理者権限推奨
#>

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

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WiFiProfiles {
    [CmdletBinding()]
    param()

    $profiles = @()

    try {
        $output = netsh wlan show profiles 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-WiFiLog -Message "WiFiプロファイルの取得に失敗しました" -Level 'ERROR'
            return $profiles
        }

        foreach ($line in $output) {
            if ($line -match "^\s*(All User Profile|すべてのユーザー プロファイル)\s*:\s*(.+)$") {
                $profileName = $matches[2].Trim()
                if ($profileName) {
                    $profiles += $profileName
                }
            }
        }
    }
    catch {
        Write-WiFiLog -Message "WiFiプロファイル取得エラー: $_" -Level 'ERROR'
    }

    return $profiles
}

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

    if ($Options.ContainsKey('BackupWiFi') -and -not $Options['BackupWiFi']) {
        Write-WiFiLog -Message "WiFiバックアップがオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    Write-WiFiLog -Message "========================================" -Level 'INFO'
    Write-WiFiLog -Message "WiFiプロファイル バックアップ開始" -Level 'INFO'
    Write-WiFiLog -Message "========================================" -Level 'INFO'

    $wlanService = Get-Service -Name "WlanSvc" -ErrorAction SilentlyContinue
    if (-not $wlanService -or $wlanService.Status -ne 'Running') {
        Write-WiFiLog -Message "WiFiサービスが利用できません（有線接続のみの環境）" -Level 'SKIP'
        return $results
    }

    $isAdmin = Test-IsAdministrator
    if (-not $isAdmin) {
        Write-WiFiLog -Message "警告: 管理者権限がないため、パスワードなしでエクスポートします" -Level 'WARNING'
    }

    $wifiBackupPath = Join-Path -Path $BackupPath -ChildPath "WiFi"
    if (-not (Test-Path -Path $wifiBackupPath)) {
        New-Item -Path $wifiBackupPath -ItemType Directory -Force | Out-Null
    }

    $profiles = Get-WiFiProfiles

    if ($profiles.Count -eq 0) {
        Write-WiFiLog -Message "保存されているWiFiプロファイルがありません" -Level 'SKIP'
        return $results
    }

    Write-WiFiLog -Message "検出されたWiFiプロファイル数: $($profiles.Count)" -Level 'INFO'

    foreach ($profileName in $profiles) {
        Write-WiFiLog -Message "エクスポート中: $profileName" -Level 'INFO'

        try {
            if ($isAdmin) {
                $null = netsh wlan export profile name="$profileName" folder="$wifiBackupPath" key=clear 2>&1
            }
            else {
                $null = netsh wlan export profile name="$profileName" folder="$wifiBackupPath" 2>&1
            }

            if ($LASTEXITCODE -eq 0) {
                Write-WiFiLog -Message "  成功: $profileName" -Level 'SUCCESS'
                $results.Success++
                $results.ProfileNames += $profileName
            }
            else {
                Write-WiFiLog -Message "  失敗: $profileName" -Level 'ERROR'
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

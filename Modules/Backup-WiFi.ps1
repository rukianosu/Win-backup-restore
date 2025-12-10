# WiFi Backup Module

function Write-WiFiLog {
    param(
        [string]$Message,
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
        'ERROR' { 'Red' }
        'SKIP' { 'Gray' }
        default { 'White' }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WiFiProfiles {
    $profiles = @()
    try {
        $output = netsh wlan show profiles 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $profiles
        }
        foreach ($line in $output) {
            if ($line -match ":\s*(.+)$") {
                $name = $matches[1].Trim()
                if ($name -and $name -notmatch "^-+$") {
                    $profiles += $name
                }
            }
        }
    }
    catch { }
    return $profiles
}

function Backup-WiFiProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        [hashtable]$Options = @{}
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
        ProfileNames = @()
    }

    if ($Options.ContainsKey('BackupWiFi') -and -not $Options['BackupWiFi']) {
        Write-WiFiLog -Message "WiFi backup skipped by option" -Level 'SKIP'
        return $results
    }

    Write-WiFiLog -Message "WiFi Profile Backup Start" -Level 'INFO'

    $wlanService = Get-Service -Name "WlanSvc" -ErrorAction SilentlyContinue
    if ($null -eq $wlanService -or $wlanService.Status -ne 'Running') {
        Write-WiFiLog -Message "WiFi service not available" -Level 'SKIP'
        return $results
    }

    $isAdmin = Test-IsAdministrator
    if (-not $isAdmin) {
        Write-WiFiLog -Message "No admin rights - exporting without password" -Level 'WARNING'
    }

    $wifiBackupPath = Join-Path -Path $BackupPath -ChildPath "WiFi"
    if (-not (Test-Path -Path $wifiBackupPath)) {
        New-Item -Path $wifiBackupPath -ItemType Directory -Force | Out-Null
    }

    $profiles = Get-WiFiProfiles
    if ($profiles.Count -eq 0) {
        Write-WiFiLog -Message "No WiFi profiles found" -Level 'SKIP'
        return $results
    }

    Write-WiFiLog -Message "Found $($profiles.Count) WiFi profiles" -Level 'INFO'

    foreach ($profileName in $profiles) {
        try {
            if ($isAdmin) {
                $null = netsh wlan export profile name="$profileName" folder="$wifiBackupPath" key=clear 2>&1
            }
            else {
                $null = netsh wlan export profile name="$profileName" folder="$wifiBackupPath" 2>&1
            }

            if ($LASTEXITCODE -eq 0) {
                Write-WiFiLog -Message "OK: $profileName" -Level 'SUCCESS'
                $results.Success++
                $results.ProfileNames += $profileName
            }
            else {
                Write-WiFiLog -Message "NG: $profileName" -Level 'ERROR'
                $results.Errors++
            }
        }
        catch {
            Write-WiFiLog -Message "Error: $profileName" -Level 'ERROR'
            $results.Errors++
        }
    }

    Write-WiFiLog -Message "WiFi Backup Complete - Success: $($results.Success)" -Level 'INFO'
    return $results
}

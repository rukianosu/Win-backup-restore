#!/usr/bin/env powershell
# -*- coding: utf-8 -*-
<#
.SYNOPSIS
    WiFiプロファイルを復元するモジュール

.DESCRIPTION
    - バックアップしたXMLファイルからWiFi設定をインポート
    - netsh wlan add profile でプロファイルを追加
    - 管理者権限が必要

.NOTES
    PowerShell 5.1 互換
    管理者権限必須
#>

#===============================================================================
# 関数: Write-WiFiRestoreLog
# 説明: WiFi復元のログを出力
#===============================================================================
function Write-WiFiRestoreLog {
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
function Test-IsAdministratorForWiFi {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#===============================================================================
# 関数: Find-WiFiBackupFolder
# 説明: バックアップ内のWiFiフォルダを検索
#===============================================================================
function Find-WiFiBackupFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupUserPath
    )

    # バックアップユーザーフォルダの親（バックアップルート）を探す
    # 例: D:\Backup_PC\Users\Username -> D:\Backup_PC\WiFi
    $usersFolder = Split-Path -Path $BackupUserPath -Parent
    $backupRoot = Split-Path -Path $usersFolder -Parent

    $wifiPath = Join-Path -Path $backupRoot -ChildPath "WiFi"

    if (Test-Path -Path $wifiPath) {
        return $wifiPath
    }

    # 見つからない場合は直接WiFiフォルダを検索
    $altPaths = @(
        (Join-Path -Path $BackupUserPath -ChildPath "WiFi"),
        (Join-Path -Path $usersFolder -ChildPath "WiFi")
    )

    foreach ($path in $altPaths) {
        if (Test-Path -Path $path) {
            return $path
        }
    }

    return $null
}

#===============================================================================
# 関数: Restore-WiFiProfiles
# 説明: XMLファイルからWiFiプロファイルをインポート
#===============================================================================
function Restore-WiFiProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Array]$SelectedUsers,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
        ProfileNames = @()
    }

    # WiFi復元オプションチェック
    if ($Options.ContainsKey('RestoreWiFi') -and -not $Options['RestoreWiFi']) {
        Write-WiFiRestoreLog -Message "WiFi復元がオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    Write-WiFiRestoreLog -Message "========================================" -Level 'INFO'
    Write-WiFiRestoreLog -Message "WiFiプロファイル 復元開始" -Level 'INFO'
    Write-WiFiRestoreLog -Message "========================================" -Level 'INFO'

    # 管理者権限チェック
    if (-not (Test-IsAdministratorForWiFi)) {
        Write-WiFiRestoreLog -Message "管理者権限がありません。WiFi復元をスキップします" -Level 'WARNING'
        Write-WiFiRestoreLog -Message "WiFiを復元するには管理者として実行してください" -Level 'WARNING'
        return $results
    }

    # WiFiサービスチェック
    $wlanService = Get-Service -Name "WlanSvc" -ErrorAction SilentlyContinue
    if (-not $wlanService -or $wlanService.Status -ne 'Running') {
        Write-WiFiRestoreLog -Message "WiFiサービスが利用できません（有線接続のみの環境）" -Level 'SKIP'
        return $results
    }

    # 最初のユーザーからWiFiフォルダを探す
    $wifiBackupPath = $null
    foreach ($user in $SelectedUsers) {
        $wifiBackupPath = Find-WiFiBackupFolder -BackupUserPath $user.UserFullPath
        if ($wifiBackupPath) {
            break
        }
    }

    if (-not $wifiBackupPath) {
        Write-WiFiRestoreLog -Message "WiFiバックアップフォルダが見つかりません" -Level 'SKIP'
        return $results
    }

    Write-WiFiRestoreLog -Message "WiFiバックアップフォルダ: $wifiBackupPath" -Level 'INFO'

    # XMLファイルを検索
    $xmlFiles = Get-ChildItem -Path $wifiBackupPath -Filter "*.xml" -ErrorAction SilentlyContinue

    if (-not $xmlFiles -or $xmlFiles.Count -eq 0) {
        Write-WiFiRestoreLog -Message "WiFiプロファイルXMLファイルがありません" -Level 'SKIP'
        return $results
    }

    Write-WiFiRestoreLog -Message "検出されたプロファイル数: $($xmlFiles.Count)" -Level 'INFO'

    # 各XMLファイルをインポート
    foreach ($xmlFile in $xmlFiles) {
        # ファイル名からプロファイル名を推測
        $profileName = $xmlFile.BaseName -replace '^Wi-Fi-', '' -replace '^Wireless Network Connection-', ''

        Write-WiFiRestoreLog -Message "インポート中: $profileName" -Level 'INFO'

        try {
            $importResult = netsh wlan add profile filename="$($xmlFile.FullName)" user=all 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-WiFiRestoreLog -Message "  成功: $profileName" -Level 'SUCCESS'
                $results.Success++
                $results.ProfileNames += $profileName
            }
            else {
                # 既に存在する場合などは警告扱い
                if ($importResult -match "already exists|既に存在") {
                    Write-WiFiRestoreLog -Message "  スキップ: $profileName （既に存在）" -Level 'SKIP'
                    $results.Skipped++
                }
                else {
                    Write-WiFiRestoreLog -Message "  失敗: $profileName - $importResult" -Level 'ERROR'
                    $results.Errors++
                }
            }
        }
        catch {
            Write-WiFiRestoreLog -Message "  エラー: $profileName - $_" -Level 'ERROR'
            $results.Errors++
        }
    }

    Write-WiFiRestoreLog -Message "========================================" -Level 'INFO'
    Write-WiFiRestoreLog -Message "WiFi復元完了" -Level 'INFO'
    Write-WiFiRestoreLog -Message "成功: $($results.Success), スキップ: $($results.Skipped), エラー: $($results.Errors)" -Level 'INFO'
    Write-WiFiRestoreLog -Message "========================================" -Level 'INFO'

    return $results
}

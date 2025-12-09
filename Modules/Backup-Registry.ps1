<#
.SYNOPSIS
    ユーザー設定系レジストリをエクスポートするモジュール

.DESCRIPTION
    - 安全なレジストリキーのみをエクスポート
    - IME設定、タブレット設定、アプリ設定を保存
    - .regファイル形式でエクスポート

.NOTES
    PowerShell 5.1 互換
#>

#===============================================================================
# エクスポート対象レジストリキー定義
#===============================================================================
$Script:ExportRegistryKeys = @(
    @{
        Name        = "IME設定"
        KeyPath     = "HKCU:\Software\Microsoft\InputMethod"
        ExportFile  = "InputMethod.reg"
        Description = "入力メソッド（IME）の設定"
    },
    @{
        Name        = "タブレット設定"
        KeyPath     = "HKCU:\Software\Microsoft\TabletTip"
        ExportFile  = "TabletTip.reg"
        Description = "タッチキーボード・手書き入力の設定"
    },
    @{
        Name        = "Microsoft IME"
        KeyPath     = "HKCU:\Software\Microsoft\IME"
        ExportFile  = "IME.reg"
        Description = "Microsoft IMEのユーザー辞書設定"
    },
    @{
        Name        = "キーボードレイアウト"
        KeyPath     = "HKCU:\Keyboard Layout"
        ExportFile  = "KeyboardLayout.reg"
        Description = "キーボードレイアウト設定"
    },
    @{
        Name        = "コンソール設定"
        KeyPath     = "HKCU:\Console"
        ExportFile  = "Console.reg"
        Description = "コマンドプロンプト・PowerShellの設定"
    },
    @{
        Name        = "環境変数"
        KeyPath     = "HKCU:\Environment"
        ExportFile  = "Environment.reg"
        Description = "ユーザー環境変数"
    },
    @{
        Name        = "エクスプローラー設定"
        KeyPath     = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        ExportFile  = "ExplorerAdvanced.reg"
        Description = "エクスプローラーの詳細設定"
    }
)

#===============================================================================
# 関数: Write-RegistryBackupLog
# 説明: レジストリバックアップのログを出力
#===============================================================================
function Write-RegistryBackupLog {
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
    $logEntry = "[$timestamp] [$Level] [Registry] $Message"

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
# 関数: Export-RegistryKey
# 説明: 指定したレジストリキーを.regファイルにエクスポート
#===============================================================================
function Export-RegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyPath,

        [Parameter(Mandatory = $true)]
        [string]$ExportFilePath,

        [Parameter(Mandatory = $false)]
        [string]$KeyName = ""
    )

    # キーパスをreg export形式に変換（HKCU: → HKEY_CURRENT_USER）
    $regKeyPath = $KeyPath -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
    $regKeyPath = $regKeyPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'

    # キーの存在チェック
    if (-not (Test-Path -Path $KeyPath -ErrorAction SilentlyContinue)) {
        Write-RegistryBackupLog -Message "[$KeyName] レジストリキーが存在しません: $KeyPath" -Level 'SKIP'
        return @{
            Success = $false
            Skipped = $true
            Error = $false
            Message = "キーが存在しません"
        }
    }

    Write-RegistryBackupLog -Message "[$KeyName] エクスポート中: $KeyPath" -Level 'INFO'

    try {
        # エクスポート先ディレクトリ作成
        $exportDir = Split-Path -Path $ExportFilePath -Parent
        if (-not (Test-Path -Path $exportDir)) {
            New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
        }

        # reg exportコマンドでエクスポート
        $result = reg export $regKeyPath $ExportFilePath /y 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-RegistryBackupLog -Message "[$KeyName] エクスポート完了: $ExportFilePath" -Level 'SUCCESS'
            return @{
                Success = $true
                Skipped = $false
                Error = $false
                Message = "エクスポート完了"
            }
        }
        else {
            Write-RegistryBackupLog -Message "[$KeyName] エクスポート失敗: $result" -Level 'ERROR'
            return @{
                Success = $false
                Skipped = $false
                Error = $true
                Message = "エクスポート失敗: $result"
            }
        }
    }
    catch {
        Write-RegistryBackupLog -Message "[$KeyName] エクスポートエラー: $_" -Level 'ERROR'
        return @{
            Success = $false
            Skipped = $false
            Error = $true
            Message = $_.Exception.Message
        }
    }
}

#===============================================================================
# 関数: Backup-UserRegistry
# 説明: ユーザー設定系レジストリをバックアップ（メイン関数）
#===============================================================================
function Backup-UserRegistry {
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

    # レジストリバックアップオプションチェック
    if ($Options.ContainsKey('BackupRegistry') -and -not $Options['BackupRegistry']) {
        Write-RegistryBackupLog -Message "レジストリバックアップがオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    Write-RegistryBackupLog -Message "========================================" -Level 'INFO'
    Write-RegistryBackupLog -Message "レジストリバックアップ処理開始" -Level 'INFO'
    Write-RegistryBackupLog -Message "========================================" -Level 'INFO'

    # レジストリ保存先ディレクトリ
    $registryBackupDir = Join-Path -Path $BackupBasePath -ChildPath "Registry"

    foreach ($regKey in $Script:ExportRegistryKeys) {
        $exportPath = Join-Path -Path $registryBackupDir -ChildPath $regKey.ExportFile

        $exportResult = Export-RegistryKey `
            -KeyPath $regKey.KeyPath `
            -ExportFilePath $exportPath `
            -KeyName $regKey.Name

        if ($exportResult.Success) {
            $results.Success++
        }
        elseif ($exportResult.Skipped) {
            $results.Skipped++
        }
        else {
            $results.Errors++
        }
    }

    # NTUSER.DATの情報を記録（復元時の参考用）
    $infoFilePath = Join-Path -Path $registryBackupDir -ChildPath "backup_info.txt"
    $infoContent = @"
===========================================
レジストリバックアップ情報
===========================================
バックアップ日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
コンピュータ名: $env:COMPUTERNAME
ユーザー名: $env:USERNAME
Windows バージョン: $([System.Environment]::OSVersion.VersionString)

エクスポートされたキー:
$($Script:ExportRegistryKeys | ForEach-Object { "  - $($_.Name): $($_.KeyPath)" } | Out-String)

復元方法:
各.regファイルをダブルクリックするか、
reg import <ファイル名.reg> コマンドで復元できます。
===========================================
"@

    try {
        $infoContent | Out-File -FilePath $infoFilePath -Encoding UTF8 -Force
        Write-RegistryBackupLog -Message "バックアップ情報ファイル作成: $infoFilePath" -Level 'SUCCESS'
    }
    catch {
        Write-RegistryBackupLog -Message "情報ファイル作成失敗: $_" -Level 'WARNING'
    }

    Write-RegistryBackupLog -Message "" -Level 'INFO'
    Write-RegistryBackupLog -Message "========================================" -Level 'INFO'
    Write-RegistryBackupLog -Message "レジストリバックアップ完了" -Level 'INFO'
    Write-RegistryBackupLog -Message "成功: $($results.Success), スキップ: $($results.Skipped), エラー: $($results.Errors)" -Level 'INFO'
    Write-RegistryBackupLog -Message "========================================" -Level 'INFO'

    return $results
}

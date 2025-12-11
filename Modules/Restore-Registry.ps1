<#
.SYNOPSIS
    ユーザー設定系レジストリを安全に復元するモジュール

.DESCRIPTION
    - バックアップからNTUSER.DATを読み込み
    - 安全なキーのみを選択的に復元
    - IME設定、タブレット設定、アプリ設定を復元
    - 危険なキー（ドライバ、サービス、セキュリティ等）は除外

.NOTES
    PowerShell 5.1 互換
    管理者権限が必要
#>

#===============================================================================
# 安全に復元可能なレジストリキー定義
#===============================================================================
$Script:SafeRegistryKeys = @(
    # IME・入力関連
    @{
        Name = "IME設定"
        SourcePath = "Software\Microsoft\InputMethod"
        Description = "入力メソッド（IME）の設定"
    },
    # タブレット・タッチ入力
    @{
        Name = "タブレット設定"
        SourcePath = "Software\Microsoft\TabletTip"
        Description = "タッチキーボード・手書き入力の設定"
    },
    # ユーザー辞書
    @{
        Name = "ユーザー辞書設定"
        SourcePath = "Software\Microsoft\IME"
        Description = "Microsoft IMEのユーザー辞書設定"
    },
    # キーボード設定
    @{
        Name = "キーボード設定"
        SourcePath = "Keyboard Layout"
        Description = "キーボードレイアウト設定"
    },
    # コンソール設定
    @{
        Name = "コンソール設定"
        SourcePath = "Console"
        Description = "コマンドプロンプト・PowerShellの設定"
    },
    # 環境変数
    @{
        Name = "環境変数"
        SourcePath = "Environment"
        Description = "ユーザー環境変数"
    },
    # デスクトップ設定（壁紙等）
    @{
        Name = "デスクトップ設定（壁紙等）"
        SourcePath = "Control Panel\Desktop"
        Description = "壁紙、スクリーンセーバー等のデスクトップ設定"
    }
)

#===============================================================================
# 復元禁止キー（セキュリティ・システム関連）
#===============================================================================
$Script:ForbiddenKeyPatterns = @(
    "*\Policies\*",           # グループポリシー
    "*\Services\*",           # サービス
    "*\Drivers\*",            # ドライバ
    "*\Security\*",           # セキュリティ
    "*\Network\*",            # ネットワーク
    "*\Tcpip\*",              # TCP/IP設定
    "*\CurrentVersion\Run*",  # スタートアップ
    "*\Authentication\*",     # 認証
    "*\Cryptography\*",       # 暗号化
    "*\Control Panel\Desktop\*ScreenSave*"  # スクリーンセーバーパスワード
)

#===============================================================================
# 関数: Write-RegistryLog
# 説明: レジストリ復元のログを出力
#===============================================================================
function Write-RegistryLog {
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
# 関数: Test-IsAdministrator
# 説明: 管理者権限で実行されているかチェック
#===============================================================================
function Test-IsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#===============================================================================
# 関数: Test-IsSafeKey
# 説明: 復元しても安全なキーかチェック
#===============================================================================
function Test-IsSafeKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyPath
    )

    foreach ($pattern in $Script:ForbiddenKeyPatterns) {
        if ($KeyPath -like $pattern) {
            return $false
        }
    }
    return $true
}

#===============================================================================
# 関数: Mount-BackupRegistry
# 説明: バックアップのNTUSER.DATをマウント
#===============================================================================
function Mount-BackupRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUserPath,

        [Parameter(Mandatory = $false)]
        [string]$MountPoint = "HKU\BackupUser"
    )

    $ntuserPath = Join-Path -Path $SourceUserPath -ChildPath "NTUSER.DAT"

    # NTUSER.DAT存在チェック
    if (-not (Test-Path -Path $ntuserPath)) {
        Write-RegistryLog -Message "NTUSER.DATが見つかりません: $ntuserPath" -Level 'WARNING'
        return $null
    }

    Write-RegistryLog -Message "レジストリハイブをマウント中: $ntuserPath" -Level 'INFO'

    try {
        # reg loadコマンドでハイブをマウント
        $result = reg load $MountPoint $ntuserPath 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-RegistryLog -Message "マウント成功: $MountPoint" -Level 'SUCCESS'
            return $MountPoint
        }
        else {
            # ファイルが使用中の場合、コピーを試みる
            Write-RegistryLog -Message "直接マウント失敗。コピーを試行..." -Level 'WARNING'

            $tempPath = Join-Path -Path $env:TEMP -ChildPath "NTUSER_BACKUP_$(Get-Date -Format 'yyyyMMddHHmmss').DAT"
            Copy-Item -Path $ntuserPath -Destination $tempPath -Force

            $result = reg load $MountPoint $tempPath 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-RegistryLog -Message "コピー経由でマウント成功: $MountPoint" -Level 'SUCCESS'
                return @{
                    MountPoint = $MountPoint
                    TempFile = $tempPath
                }
            }
            else {
                Write-RegistryLog -Message "マウント失敗: $result" -Level 'ERROR'
                return $null
            }
        }
    }
    catch {
        Write-RegistryLog -Message "マウントエラー: $_" -Level 'ERROR'
        return $null
    }
}

#===============================================================================
# 関数: Dismount-BackupRegistry
# 説明: マウントしたレジストリハイブをアンマウント
#===============================================================================
function Dismount-BackupRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MountPoint,

        [Parameter(Mandatory = $false)]
        [string]$TempFile = ""
    )

    Write-RegistryLog -Message "レジストリハイブをアンマウント中: $MountPoint" -Level 'INFO'

    try {
        # ガベージコレクションを実行（ハンドルを解放）
        [gc]::Collect()
        Start-Sleep -Seconds 1

        $result = reg unload $MountPoint 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-RegistryLog -Message "アンマウント成功" -Level 'SUCCESS'
        }
        else {
            Write-RegistryLog -Message "アンマウント警告: $result" -Level 'WARNING'
        }

        # 一時ファイルがあれば削除
        if ($TempFile -and (Test-Path -Path $TempFile)) {
            Remove-Item -Path $TempFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-RegistryLog -Message "アンマウントエラー: $_" -Level 'ERROR'
    }
}

#===============================================================================
# 関数: Copy-RegistryKey
# 説明: レジストリキーを復元（再帰的）
#===============================================================================
function Copy-RegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceKey,

        [Parameter(Mandatory = $true)]
        [string]$DestinationKey
    )

    # 安全性チェック
    if (-not (Test-IsSafeKey -KeyPath $SourceKey)) {
        Write-RegistryLog -Message "安全でないキーをスキップ: $SourceKey" -Level 'SKIP'
        return @{ Success = $false; Skipped = $true; Error = $false }
    }

    try {
        # ソースキーの存在チェック
        $sourceRegKey = Get-Item -Path "Registry::$SourceKey" -ErrorAction SilentlyContinue
        if (-not $sourceRegKey) {
            Write-RegistryLog -Message "ソースキーが存在しません: $SourceKey" -Level 'SKIP'
            return @{ Success = $false; Skipped = $true; Error = $false }
        }

        # 宛先キーの作成
        $destRegKey = Get-Item -Path "Registry::$DestinationKey" -ErrorAction SilentlyContinue
        if (-not $destRegKey) {
            New-Item -Path "Registry::$DestinationKey" -Force | Out-Null
            Write-RegistryLog -Message "宛先キー作成: $DestinationKey" -Level 'INFO'
        }

        # 値をコピー
        $values = Get-ItemProperty -Path "Registry::$SourceKey" -ErrorAction SilentlyContinue
        if ($values) {
            $valueNames = $values.PSObject.Properties | Where-Object {
                $_.Name -notlike 'PS*'
            }

            foreach ($prop in $valueNames) {
                try {
                    Set-ItemProperty -Path "Registry::$DestinationKey" -Name $prop.Name -Value $prop.Value -Force
                }
                catch {
                    Write-RegistryLog -Message "値のコピー失敗: $($prop.Name) - $_" -Level 'WARNING'
                }
            }
        }

        # サブキーを再帰的にコピー
        $subKeys = Get-ChildItem -Path "Registry::$SourceKey" -ErrorAction SilentlyContinue
        foreach ($subKey in $subKeys) {
            $subSourcePath = "$SourceKey\$($subKey.PSChildName)"
            $subDestPath = "$DestinationKey\$($subKey.PSChildName)"

            # 再帰呼び出し
            Copy-RegistryKey -SourceKey $subSourcePath -DestinationKey $subDestPath
        }

        return @{ Success = $true; Skipped = $false; Error = $false }
    }
    catch {
        Write-RegistryLog -Message "キーコピーエラー: $SourceKey - $_" -Level 'ERROR'
        return @{ Success = $false; Skipped = $false; Error = $true }
    }
}

#===============================================================================
# 関数: Restore-SafeRegistryKeys
# 説明: 安全なレジストリキーのみを復元
#===============================================================================
function Restore-SafeRegistryKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MountPoint
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    Write-RegistryLog -Message "=== 安全なレジストリキーの復元開始 ===" -Level 'INFO'

    foreach ($keyInfo in $Script:SafeRegistryKeys) {
        Write-RegistryLog -Message "[$($keyInfo.Name)] 復元中..." -Level 'INFO'

        $sourceKey = "$MountPoint\$($keyInfo.SourcePath)"
        $destKey = "HKEY_CURRENT_USER\$($keyInfo.SourcePath)"

        $copyResult = Copy-RegistryKey -SourceKey $sourceKey -DestinationKey $destKey

        if ($copyResult.Success) {
            Write-RegistryLog -Message "[$($keyInfo.Name)] 復元成功" -Level 'SUCCESS'
            $results.Success++
        }
        elseif ($copyResult.Skipped) {
            Write-RegistryLog -Message "[$($keyInfo.Name)] スキップ" -Level 'SKIP'
            $results.Skipped++
        }
        else {
            Write-RegistryLog -Message "[$($keyInfo.Name)] 復元失敗" -Level 'ERROR'
            $results.Errors++
        }
    }

    return $results
}

#===============================================================================
# 関数: Restore-Wallpaper
# 説明: 壁紙を復元して適用
#===============================================================================
function Restore-Wallpaper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUserPath
    )

    $results = @{
        Success = $false
        Message = ""
    }

    # バックアップされた壁紙フォルダを探す
    $wallpaperBackupDir = Join-Path -Path $SourceUserPath -ChildPath "Registry\Wallpaper"

    if (-not (Test-Path -Path $wallpaperBackupDir)) {
        Write-RegistryLog -Message "[壁紙] バックアップされた壁紙が見つかりません" -Level 'SKIP'
        return $results
    }

    # 壁紙画像ファイルを探す
    $wallpaperFiles = Get-ChildItem -Path $wallpaperBackupDir -File | Where-Object { $_.Extension -match '\.(jpg|jpeg|png|bmp|gif)$' }

    if (-not $wallpaperFiles -or $wallpaperFiles.Count -eq 0) {
        Write-RegistryLog -Message "[壁紙] 壁紙画像ファイルが見つかりません" -Level 'SKIP'
        return $results
    }

    $sourceWallpaper = $wallpaperFiles[0].FullName
    Write-RegistryLog -Message "[壁紙] バックアップ壁紙を発見: $($wallpaperFiles[0].Name)" -Level 'INFO'

    try {
        # 壁紙を現在のユーザーのPicturesフォルダにコピー
        $destWallpaperDir = Join-Path -Path $env:USERPROFILE -ChildPath "Pictures\Wallpapers"
        if (-not (Test-Path -Path $destWallpaperDir)) {
            New-Item -Path $destWallpaperDir -ItemType Directory -Force | Out-Null
        }

        $destWallpaperPath = Join-Path -Path $destWallpaperDir -ChildPath $wallpaperFiles[0].Name
        Copy-Item -Path $sourceWallpaper -Destination $destWallpaperPath -Force

        Write-RegistryLog -Message "[壁紙] 画像をコピー: $destWallpaperPath" -Level 'SUCCESS'

        # Windows APIで壁紙を適用
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    public const int SPI_SETDESKWALLPAPER = 0x0014;
    public const int SPIF_UPDATEINIFILE = 0x01;
    public const int SPIF_SENDCHANGE = 0x02;
}
"@ -ErrorAction SilentlyContinue

        $result = [Wallpaper]::SystemParametersInfo(
            [Wallpaper]::SPI_SETDESKWALLPAPER,
            0,
            $destWallpaperPath,
            [Wallpaper]::SPIF_UPDATEINIFILE -bor [Wallpaper]::SPIF_SENDCHANGE
        )

        if ($result -ne 0) {
            Write-RegistryLog -Message "[壁紙] 壁紙を適用しました" -Level 'SUCCESS'
            $results.Success = $true
            $results.Message = "壁紙を適用しました"
        }
        else {
            Write-RegistryLog -Message "[壁紙] 壁紙の適用に失敗しました（APIエラー）" -Level 'WARNING'
            $results.Message = "APIエラー"
        }
    }
    catch {
        Write-RegistryLog -Message "[壁紙] 壁紙の復元に失敗: $_" -Level 'WARNING'
        $results.Message = $_.Exception.Message
    }

    return $results
}

#===============================================================================
# 関数: Restore-UserRegistry
# 説明: ユーザーレジストリを復元（メイン関数）
#===============================================================================
function Restore-UserRegistry {
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

    # レジストリ復元オプションチェック
    if ($Options.ContainsKey('RestoreRegistry') -and -not $Options['RestoreRegistry']) {
        Write-RegistryLog -Message "レジストリ復元がオプションでスキップされました" -Level 'SKIP'
        return $totalResults
    }

    # 管理者権限チェック
    if (-not (Test-IsAdministrator)) {
        Write-RegistryLog -Message "警告: 管理者権限がありません。レジストリ復元をスキップします" -Level 'WARNING'
        Write-RegistryLog -Message "レジストリを復元するには、管理者として実行してください" -Level 'WARNING'
        return $totalResults
    }

    Write-RegistryLog -Message "========================================" -Level 'INFO'
    Write-RegistryLog -Message "レジストリ復元処理開始" -Level 'INFO'
    Write-RegistryLog -Message "========================================" -Level 'INFO'

    foreach ($user in $SelectedUsers) {
        Write-Host ""
        Write-RegistryLog -Message "--- ユーザー: $($user.UserName) のレジストリ復元 ---" -Level 'INFO'

        # レジストリハイブをマウント
        $mountResult = Mount-BackupRegistry -SourceUserPath $user.UserFullPath

        if (-not $mountResult) {
            Write-RegistryLog -Message "レジストリのマウントに失敗しました" -Level 'ERROR'
            $totalResults.Errors++
            continue
        }

        # マウントポイントを取得
        $mountPoint = if ($mountResult -is [hashtable]) {
            $mountResult.MountPoint
        } else {
            $mountResult
        }

        $tempFile = if ($mountResult -is [hashtable]) {
            $mountResult.TempFile
        } else {
            ""
        }

        try {
            # 安全なキーを復元
            $restoreResult = Restore-SafeRegistryKeys -MountPoint $mountPoint
            $totalResults.Success += $restoreResult.Success
            $totalResults.Skipped += $restoreResult.Skipped
            $totalResults.Errors += $restoreResult.Errors
        }
        finally {
            # 必ずアンマウント
            Dismount-BackupRegistry -MountPoint $mountPoint -TempFile $tempFile
        }

        # 壁紙を復元（レジストリとは別に画像ファイルを適用）
        $wallpaperResult = Restore-Wallpaper -SourceUserPath $user.UserFullPath
        if ($wallpaperResult.Success) {
            $totalResults.Success++
        }
    }

    Write-Host ""
    Write-RegistryLog -Message "========================================" -Level 'INFO'
    Write-RegistryLog -Message "レジストリ復元完了" -Level 'INFO'
    Write-RegistryLog -Message "成功: $($totalResults.Success), スキップ: $($totalResults.Skipped), エラー: $($totalResults.Errors)" -Level 'INFO'
    Write-RegistryLog -Message "========================================" -Level 'INFO'

    return $totalResults
}

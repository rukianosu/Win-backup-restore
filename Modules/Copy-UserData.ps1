<#
.SYNOPSIS
    robocopyを使用してユーザーデータをコピーするモジュール

.DESCRIPTION
    - 選択されたユーザーフォルダを現在のユーザープロファイルにコピー
    - Desktop, Documents, Pictures, Videos, Music, Downloads を復元
    - AppData内の辞書・テーマを復元
    - OneDrive, Dropbox, iCloud, GoogleDriveが存在すれば復元
    - フォルダがない場合は自動スキップ

.NOTES
    PowerShell 5.1 互換
    robocopy使用
#>

#===============================================================================
# グローバル設定
#===============================================================================
$Script:LogPath = "C:\AutoSetup\Logs\Restore.log"

#===============================================================================
# 復元対象フォルダ定義
#===============================================================================
$Script:StandardFolders = @(
    @{ Name = "Desktop";    Source = "Desktop";    Target = "Desktop" },
    @{ Name = "Documents";  Source = "Documents";  Target = "Documents" },
    @{ Name = "Pictures";   Source = "Pictures";   Target = "Pictures" },
    @{ Name = "Videos";     Source = "Videos";     Target = "Videos" },
    @{ Name = "Music";      Source = "Music";      Target = "Music" },
    @{ Name = "Downloads";  Source = "Downloads";  Target = "Downloads" }
)

$Script:AppDataFolders = @(
    @{
        Name   = "辞書（Dictionaries）"
        Source = "AppData\Roaming\Microsoft\Windows\Dictionaries"
        Target = "AppData\Roaming\Microsoft\Windows\Dictionaries"
    },
    @{
        Name   = "テーマ（Themes）"
        Source = "AppData\Roaming\Microsoft\Windows\Themes"
        Target = "AppData\Roaming\Microsoft\Windows\Themes"
    }
)

$Script:CloudDriveFolders = @(
    @{ Name = "OneDrive";     Source = "OneDrive";           Target = "OneDrive" },
    @{ Name = "Dropbox";      Source = "Dropbox";            Target = "Dropbox" },
    @{ Name = "iCloudDrive";  Source = "iCloudDrive";        Target = "iCloudDrive" },
    @{ Name = "GoogleDrive";  Source = "Google Drive";       Target = "Google Drive" },
    @{ Name = "GoogleDrive2"; Source = "GoogleDrive";        Target = "GoogleDrive" }
)

#===============================================================================
# 関数: Write-RestoreLog
# 説明: ログファイルに書き込み
#===============================================================================
function Write-RestoreLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'SKIP')]
        [string]$Level = 'INFO'
    )

    # ログディレクトリ作成
    $logDir = Split-Path -Path $Script:LogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # タイムスタンプ付きでログ出力
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # ファイルとコンソールに出力
    Add-Content -Path $Script:LogPath -Value $logEntry -Encoding UTF8

    # コンソール出力（色分け）
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
# 関数: Invoke-RobocopyWithLog
# 説明: robocopyを実行してログを記録
#===============================================================================
function Invoke-RobocopyWithLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $false)]
        [string]$FolderName = "",

        [Parameter(Mandatory = $false)]
        [switch]$Mirror = $false
    )

    # ソースフォルダ存在チェック
    if (-not (Test-Path -Path $Source)) {
        Write-RestoreLog -Message "[$FolderName] ソースフォルダが存在しません: $Source" -Level 'SKIP'
        return @{
            Success = $false
            Skipped = $true
            Error = $false
            Message = "ソースフォルダなし"
        }
    }

    # 宛先フォルダの親ディレクトリ作成
    $destParent = Split-Path -Path $Destination -Parent
    if (-not (Test-Path -Path $destParent)) {
        New-Item -Path $destParent -ItemType Directory -Force | Out-Null
    }

    Write-RestoreLog -Message "[$FolderName] コピー開始: $Source -> $Destination" -Level 'INFO'

    try {
        # robocopyオプション設定
        # /E = 空のサブディレクトリも含めてコピー
        # /COPYALL = すべてのファイル情報をコピー（データ、属性、タイムスタンプ等）
        # /R:3 = 失敗時のリトライ回数
        # /W:5 = リトライ間隔（秒）
        # /MT:8 = マルチスレッド（8スレッド）
        # /NP = 進捗表示なし
        # /NFL = ファイルリスト非表示
        # /NDL = ディレクトリリスト非表示
        # /XJ = ジャンクションを除外

        $robocopyArgs = @(
            "`"$Source`"",
            "`"$Destination`"",
            "/E",
            "/COPY:DAT",
            "/R:3",
            "/W:5",
            "/MT:8",
            "/NP",
            "/XJ",
            "/XO"  # 新しいファイルのみコピー（上書き保護）
        )

        # Mirrorモードの場合は /MIR を追加（削除も行う）
        if ($Mirror) {
            $robocopyArgs = @(
                "`"$Source`"",
                "`"$Destination`"",
                "/MIR",
                "/COPY:DAT",
                "/R:3",
                "/W:5",
                "/MT:8",
                "/NP",
                "/XJ"
            )
        }

        $argString = $robocopyArgs -join " "
        $result = cmd /c "robocopy $argString 2>&1"
        $exitCode = $LASTEXITCODE

        # robocopy終了コードの解釈
        # 0 = 何もコピーしなかった（ファイルは既に同期済み）
        # 1 = ファイルを正常にコピーした
        # 2 = 追加のファイルが宛先にあった
        # 3 = 1+2
        # 4 = 一部の不一致ファイルまたはディレクトリが検出された
        # 8 = 一部のファイルまたはディレクトリがコピーできなかった（エラー）
        # 16 = 致命的エラー

        if ($exitCode -lt 8) {
            Write-RestoreLog -Message "[$FolderName] コピー完了 (終了コード: $exitCode)" -Level 'SUCCESS'
            return @{
                Success = $true
                Skipped = $false
                Error = $false
                Message = "コピー完了"
                ExitCode = $exitCode
            }
        }
        else {
            Write-RestoreLog -Message "[$FolderName] コピーエラー (終了コード: $exitCode)" -Level 'ERROR'
            return @{
                Success = $false
                Skipped = $false
                Error = $true
                Message = "robocopyエラー: $exitCode"
                ExitCode = $exitCode
            }
        }
    }
    catch {
        Write-RestoreLog -Message "[$FolderName] 例外エラー: $_" -Level 'ERROR'
        return @{
            Success = $false
            Skipped = $false
            Error = $true
            Message = $_.Exception.Message
        }
    }
}

#===============================================================================
# 関数: Copy-StandardFolders
# 説明: 標準フォルダ（Desktop, Documents等）をコピー
#===============================================================================
function Copy-StandardFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUserPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    $currentUserProfile = $env:USERPROFILE

    Write-RestoreLog -Message "=== 標準フォルダの復元開始 ===" -Level 'INFO'

    foreach ($folder in $Script:StandardFolders) {
        # オプションチェック
        $optionName = "Restore$($folder.Name)"
        if ($Options.ContainsKey($optionName) -and -not $Options[$optionName]) {
            Write-RestoreLog -Message "[$($folder.Name)] オプションでスキップ" -Level 'SKIP'
            $results.Skipped++
            continue
        }

        $sourcePath = Join-Path -Path $SourceUserPath -ChildPath $folder.Source
        $destPath = Join-Path -Path $currentUserProfile -ChildPath $folder.Target

        $copyResult = Invoke-RobocopyWithLog -Source $sourcePath -Destination $destPath -FolderName $folder.Name

        if ($copyResult.Success) {
            $results.Success++
        }
        elseif ($copyResult.Skipped) {
            $results.Skipped++
        }
        else {
            $results.Errors++
        }
    }

    return $results
}

#===============================================================================
# 関数: Copy-AppDataFolders
# 説明: AppData内のフォルダ（辞書・テーマ）をコピー
#===============================================================================
function Copy-AppDataFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUserPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    # AppData復元オプションチェック
    if ($Options.ContainsKey('RestoreAppData') -and -not $Options['RestoreAppData']) {
        Write-RestoreLog -Message "AppData復元がオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    $currentUserProfile = $env:USERPROFILE

    Write-RestoreLog -Message "=== AppDataフォルダの復元開始 ===" -Level 'INFO'

    foreach ($folder in $Script:AppDataFolders) {
        $sourcePath = Join-Path -Path $SourceUserPath -ChildPath $folder.Source
        $destPath = Join-Path -Path $currentUserProfile -ChildPath $folder.Target

        $copyResult = Invoke-RobocopyWithLog -Source $sourcePath -Destination $destPath -FolderName $folder.Name

        if ($copyResult.Success) {
            $results.Success++
        }
        elseif ($copyResult.Skipped) {
            $results.Skipped++
        }
        else {
            $results.Errors++
        }
    }

    return $results
}

#===============================================================================
# 関数: Copy-CloudDriveFolders
# 説明: クラウドドライブフォルダをコピー（存在する場合のみ）
#===============================================================================
function Copy-CloudDriveFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUserPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Options
    )

    $results = @{
        Success = 0
        Skipped = 0
        Errors = 0
    }

    # クラウドドライブ復元オプションチェック
    if ($Options.ContainsKey('RestoreCloudDrive') -and -not $Options['RestoreCloudDrive']) {
        Write-RestoreLog -Message "クラウドドライブ復元がオプションでスキップされました" -Level 'SKIP'
        return $results
    }

    $currentUserProfile = $env:USERPROFILE

    Write-RestoreLog -Message "=== クラウドドライブの復元開始 ===" -Level 'INFO'

    foreach ($folder in $Script:CloudDriveFolders) {
        $sourcePath = Join-Path -Path $SourceUserPath -ChildPath $folder.Source

        # 存在チェック（クラウドドライブは存在しない場合が多い）
        if (-not (Test-Path -Path $sourcePath)) {
            # クラウドドライブは存在しなくても正常なのでログは簡略化
            continue
        }

        $destPath = Join-Path -Path $currentUserProfile -ChildPath $folder.Target

        Write-RestoreLog -Message "[$($folder.Name)] クラウドドライブ発見: $sourcePath" -Level 'INFO'

        $copyResult = Invoke-RobocopyWithLog -Source $sourcePath -Destination $destPath -FolderName $folder.Name

        if ($copyResult.Success) {
            $results.Success++
        }
        elseif ($copyResult.Skipped) {
            $results.Skipped++
        }
        else {
            $results.Errors++
        }
    }

    return $results
}

#===============================================================================
# 関数: Copy-AllUserData
# 説明: すべてのユーザーデータをコピー（メイン関数）
#===============================================================================
function Copy-AllUserData {
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

    Write-RestoreLog -Message "========================================" -Level 'INFO'
    Write-RestoreLog -Message "ユーザーデータ復元処理開始" -Level 'INFO'
    Write-RestoreLog -Message "対象ユーザー数: $($SelectedUsers.Count)" -Level 'INFO'
    Write-RestoreLog -Message "========================================" -Level 'INFO'

    foreach ($user in $SelectedUsers) {
        Write-RestoreLog -Message "" -Level 'INFO'
        Write-RestoreLog -Message "--- ユーザー: $($user.UserName) の復元開始 ---" -Level 'INFO'
        Write-RestoreLog -Message "ソースパス: $($user.UserFullPath)" -Level 'INFO'

        # 標準フォルダをコピー
        $standardResult = Copy-StandardFolders -SourceUserPath $user.UserFullPath -Options $Options
        $totalResults.Success += $standardResult.Success
        $totalResults.Skipped += $standardResult.Skipped
        $totalResults.Errors += $standardResult.Errors

        # AppDataフォルダをコピー
        $appDataResult = Copy-AppDataFolders -SourceUserPath $user.UserFullPath -Options $Options
        $totalResults.Success += $appDataResult.Success
        $totalResults.Skipped += $appDataResult.Skipped
        $totalResults.Errors += $appDataResult.Errors

        # クラウドドライブをコピー
        $cloudResult = Copy-CloudDriveFolders -SourceUserPath $user.UserFullPath -Options $Options
        $totalResults.Success += $cloudResult.Success
        $totalResults.Skipped += $cloudResult.Skipped
        $totalResults.Errors += $cloudResult.Errors

        Write-RestoreLog -Message "--- ユーザー: $($user.UserName) の復元完了 ---" -Level 'INFO'
    }

    Write-RestoreLog -Message "" -Level 'INFO'
    Write-RestoreLog -Message "========================================" -Level 'INFO'
    Write-RestoreLog -Message "ユーザーデータ復元処理完了" -Level 'INFO'
    Write-RestoreLog -Message "成功: $($totalResults.Success), スキップ: $($totalResults.Skipped), エラー: $($totalResults.Errors)" -Level 'INFO'
    Write-RestoreLog -Message "========================================" -Level 'INFO'

    return $totalResults
}

<#
.SYNOPSIS
    バックアップ/復元の検証モジュール

.DESCRIPTION
    - ソースと宛先のファイル数を比較
    - 合計サイズを比較
    - 検証レポートを表示

.NOTES
    PowerShell 5.1 互換
#>

#===============================================================================
# 関数: Write-VerifyLog
# 説明: 検証ログを出力
#===============================================================================
function Write-VerifyLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [Verify] $Message"

    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        default   { 'White' }
    }
    Write-Host $logEntry -ForegroundColor $color
}

#===============================================================================
# 関数: Get-FolderStats
# 説明: フォルダのファイル数とサイズを取得
#===============================================================================
function Get-FolderStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$FolderName = ""
    )

    $stats = @{
        Path = $Path
        Name = $FolderName
        FileCount = 0
        TotalSize = 0
        Exists = $false
    }

    if (-not (Test-Path -Path $Path)) {
        return $stats
    }

    $stats.Exists = $true

    try {
        # ファイル情報を取得（ジャンクションを除外）
        $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) }

        if ($files) {
            $stats.FileCount = $files.Count
            $stats.TotalSize = ($files | Measure-Object -Property Length -Sum).Sum
        }
    }
    catch {
        # エラーがあっても続行
    }

    return $stats
}

#===============================================================================
# 関数: Format-FileSize
# 説明: バイト数を読みやすい形式に変換
#===============================================================================
function Format-FileSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [long]$Bytes
    )

    if ($Bytes -ge 1TB) {
        return "{0:N2} TB" -f ($Bytes / 1TB)
    }
    elseif ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
    }
}

#===============================================================================
# 関数: Compare-FolderPair
# 説明: ソースと宛先のフォルダを比較
#===============================================================================
function Compare-FolderPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestPath,

        [Parameter(Mandatory = $true)]
        [string]$FolderName
    )

    $result = @{
        Name = $FolderName
        SourceFiles = 0
        DestFiles = 0
        SourceSize = 0
        DestSize = 0
        FilesMatch = $false
        SizeMatch = $false
        Status = "SKIP"
    }

    # ソースが存在しない場合はスキップ
    if (-not (Test-Path -Path $SourcePath)) {
        $result.Status = "SKIP"
        return $result
    }

    Write-Host "  検証中: $FolderName..." -ForegroundColor Cyan -NoNewline

    $sourceStats = Get-FolderStats -Path $SourcePath -FolderName $FolderName
    $destStats = Get-FolderStats -Path $DestPath -FolderName $FolderName

    $result.SourceFiles = $sourceStats.FileCount
    $result.DestFiles = $destStats.FileCount
    $result.SourceSize = $sourceStats.TotalSize
    $result.DestSize = $destStats.TotalSize

    # ファイル数の比較（差分バックアップでは宛先が多いこともある）
    $result.FilesMatch = ($result.DestFiles -ge $result.SourceFiles * 0.95)

    # サイズの比較（5%以内の差は許容）
    if ($result.SourceSize -eq 0) {
        $result.SizeMatch = ($result.DestSize -eq 0)
    }
    else {
        $sizeDiff = [Math]::Abs($result.SourceSize - $result.DestSize) / $result.SourceSize
        $result.SizeMatch = ($sizeDiff -lt 0.05)
    }

    # ステータス判定
    if ($result.FilesMatch -and $result.SizeMatch) {
        $result.Status = "OK"
        Write-Host "`r  検証中: $FolderName... OK                    " -ForegroundColor Green
    }
    elseif ($result.DestFiles -eq 0 -and $result.SourceFiles -gt 0) {
        $result.Status = "FAIL"
        Write-Host "`r  検証中: $FolderName... FAIL (コピーされていない)" -ForegroundColor Red
    }
    else {
        $result.Status = "WARN"
        Write-Host "`r  検証中: $FolderName... WARN (差異あり)        " -ForegroundColor Yellow
    }

    return $result
}

#===============================================================================
# 関数: Show-VerificationReport
# 説明: 検証レポートを表示
#===============================================================================
function Show-VerificationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Array]$Results,

        [Parameter(Mandatory = $false)]
        [string]$Title = "バックアップ検証レポート"
    )

    $totalSourceFiles = 0
    $totalDestFiles = 0
    $totalSourceSize = 0
    $totalDestSize = 0
    $okCount = 0
    $warnCount = 0
    $failCount = 0
    $skipCount = 0

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("{0,-20} {1,12} {2,12} {3,10}" -f "フォルダ", "ソース", "コピー先", "結果")
    Write-Host ("{0,-20} {1,12} {2,12} {3,10}" -f "--------", "------", "--------", "----")

    foreach ($r in $Results) {
        if ($r.Status -eq "SKIP") {
            $skipCount++
            continue
        }

        $totalSourceFiles += $r.SourceFiles
        $totalDestFiles += $r.DestFiles
        $totalSourceSize += $r.SourceSize
        $totalDestSize += $r.DestSize

        $statusColor = switch ($r.Status) {
            "OK" { "Green"; $okCount++ }
            "WARN" { "Yellow"; $warnCount++ }
            "FAIL" { "Red"; $failCount++ }
            default { "White" }
        }

        $statusIcon = switch ($r.Status) {
            "OK" { "[OK]" }
            "WARN" { "[!]" }
            "FAIL" { "[X]" }
            default { "[-]" }
        }

        Write-Host ("{0,-20} {1,10}件 {2,10}件 " -f $r.Name, $r.SourceFiles, $r.DestFiles) -NoNewline
        Write-Host $statusIcon -ForegroundColor $statusColor
    }

    Write-Host ""
    Write-Host ("{0,-20} {1,12} {2,12}" -f "--------", "------", "--------")

    # 合計
    $sourceTotal = Format-FileSize -Bytes $totalSourceSize
    $destTotal = Format-FileSize -Bytes $totalDestSize

    Write-Host ("{0,-20} {1,10}件 {2,10}件" -f "合計ファイル数", $totalSourceFiles, $totalDestFiles)
    Write-Host ("{0,-20} {1,12} {2,12}" -f "合計サイズ", $sourceTotal, $destTotal)

    Write-Host ""

    # サイズ一致チェック
    if ($totalSourceSize -gt 0) {
        $sizeDiffPercent = [Math]::Abs($totalSourceSize - $totalDestSize) / $totalSourceSize * 100
        if ($sizeDiffPercent -lt 1) {
            Write-Host "サイズ検証: OK (差異 $("{0:N2}" -f $sizeDiffPercent)%)" -ForegroundColor Green
        }
        elseif ($sizeDiffPercent -lt 5) {
            Write-Host "サイズ検証: OK (差異 $("{0:N2}" -f $sizeDiffPercent)%)" -ForegroundColor Yellow
        }
        else {
            Write-Host "サイズ検証: 警告 (差異 $("{0:N2}" -f $sizeDiffPercent)%)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan

    # 結果サマリー
    if ($failCount -gt 0) {
        Write-Host " 結果: 問題あり ($failCount 件の失敗)" -ForegroundColor Red
    }
    elseif ($warnCount -gt 0) {
        Write-Host " 結果: 一部に差異あり ($warnCount 件)" -ForegroundColor Yellow
    }
    else {
        Write-Host " 結果: すべて正常" -ForegroundColor Green
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    return @{
        OK = $okCount
        Warn = $warnCount
        Fail = $failCount
        Skip = $skipCount
        TotalSourceFiles = $totalSourceFiles
        TotalDestFiles = $totalDestFiles
        TotalSourceSize = $totalSourceSize
        TotalDestSize = $totalDestSize
    }
}

#===============================================================================
# 関数: Invoke-BackupVerification
# 説明: バックアップの検証を実行
#===============================================================================
function Invoke-BackupVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceBasePath,

        [Parameter(Mandatory = $true)]
        [string]$DestBasePath,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    Write-VerifyLog -Message "バックアップ検証を開始します..." -Level 'INFO'
    Write-Host ""

    $results = @()

    # 標準フォルダの検証
    $standardFolders = @("Desktop", "Documents", "Pictures", "Videos", "Music", "Downloads")

    foreach ($folder in $standardFolders) {
        $sourcePath = Join-Path -Path $SourceBasePath -ChildPath $folder
        $destPath = Join-Path -Path $DestBasePath -ChildPath $folder

        $result = Compare-FolderPair -SourcePath $sourcePath -DestPath $destPath -FolderName $folder
        $results += $result
    }

    # クラウドドライブの検証
    $cloudFolders = @("OneDrive", "Dropbox", "iCloudDrive", "Google Drive", "GoogleDrive")

    foreach ($folder in $cloudFolders) {
        $sourcePath = Join-Path -Path $SourceBasePath -ChildPath $folder
        if (Test-Path -Path $sourcePath) {
            $destPath = Join-Path -Path $DestBasePath -ChildPath $folder
            $result = Compare-FolderPair -SourcePath $sourcePath -DestPath $destPath -FolderName $folder
            $results += $result
        }
    }

    # レポート表示
    $summary = Show-VerificationReport -Results $results -Title "バックアップ検証レポート"

    return $summary
}

#===============================================================================
# 関数: Invoke-RestoreVerification
# 説明: 復元の検証を実行
#===============================================================================
function Invoke-RestoreVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceBasePath,

        [Parameter(Mandatory = $true)]
        [string]$DestBasePath,

        [Parameter(Mandatory = $false)]
        [hashtable]$Options = @{}
    )

    Write-VerifyLog -Message "復元検証を開始します..." -Level 'INFO'
    Write-Host ""

    $results = @()

    # 標準フォルダの検証
    $standardFolders = @("Desktop", "Documents", "Pictures", "Videos", "Music", "Downloads")

    foreach ($folder in $standardFolders) {
        $sourcePath = Join-Path -Path $SourceBasePath -ChildPath $folder
        $destPath = Join-Path -Path $DestBasePath -ChildPath $folder

        $result = Compare-FolderPair -SourcePath $sourcePath -DestPath $destPath -FolderName $folder
        $results += $result
    }

    # クラウドドライブの検証
    $cloudFolders = @("OneDrive", "Dropbox", "iCloudDrive", "Google Drive", "GoogleDrive")

    foreach ($folder in $cloudFolders) {
        $sourcePath = Join-Path -Path $SourceBasePath -ChildPath $folder
        if (Test-Path -Path $sourcePath) {
            $destPath = Join-Path -Path $DestBasePath -ChildPath $folder
            $result = Compare-FolderPair -SourcePath $sourcePath -DestPath $destPath -FolderName $folder
            $results += $result
        }
    }

    # レポート表示
    $summary = Show-VerificationReport -Results $results -Title "復元検証レポート"

    return $summary
}

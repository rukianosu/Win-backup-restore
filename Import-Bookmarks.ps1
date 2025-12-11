<#
.SYNOPSIS
    Chrome / Edge のブックマークをインポート（復元）

.DESCRIPTION
    バックアップした Bookmarks ファイルを復元する
    既存ファイルは .bak として退避してから上書き
    ブラウザは事前に閉じておくこと
#>

# ブックマークファイルのパス（固定）
$ChromeBookmarks = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks"
$EdgeBookmarks = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"

# バックアップ元フォルダを入力
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " ブックマーク インポート" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "※ ブラウザを閉じてから実行してください" -ForegroundColor Yellow
Write-Host ""

$BackupPath = Read-Host "バックアップ元フォルダを入力してください"

if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    Write-Host "フォルダが指定されていません。終了します。" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $BackupPath)) {
    Write-Host "フォルダが存在しません: $BackupPath" -ForegroundColor Red
    exit 1
}

# 日付サフィックス
$DateSuffix = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host ""
Write-Host "--- Chrome ---" -ForegroundColor Cyan

# Chrome Bookmarks 復元
$ChromeBackup = Join-Path -Path $BackupPath -ChildPath "Chrome_Bookmarks"
if (Test-Path -Path $ChromeBackup) {
    # 復元先フォルダを作成
    $ChromeDir = Split-Path -Path $ChromeBookmarks -Parent
    if (-not (Test-Path -Path $ChromeDir)) {
        New-Item -Path $ChromeDir -ItemType Directory -Force | Out-Null
        Write-Host "フォルダ作成: $ChromeDir" -ForegroundColor Green
    }

    # 既存ファイルを退避
    if (Test-Path -Path $ChromeBookmarks) {
        $ChromeBak = "$ChromeBookmarks.bak-$DateSuffix"
        Copy-Item -Path $ChromeBookmarks -Destination $ChromeBak -Force
        Write-Host "退避: $ChromeBak" -ForegroundColor Gray
    }

    # 復元
    Copy-Item -Path $ChromeBackup -Destination $ChromeBookmarks -Force
    Write-Host "OK: $ChromeBookmarks" -ForegroundColor Green
}
else {
    Write-Host "Chrome バックアップが見つかりません: $ChromeBackup" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- Edge ---" -ForegroundColor Cyan

# Edge Bookmarks 復元
$EdgeBackup = Join-Path -Path $BackupPath -ChildPath "Edge_Bookmarks"
if (Test-Path -Path $EdgeBackup) {
    # 復元先フォルダを作成
    $EdgeDir = Split-Path -Path $EdgeBookmarks -Parent
    if (-not (Test-Path -Path $EdgeDir)) {
        New-Item -Path $EdgeDir -ItemType Directory -Force | Out-Null
        Write-Host "フォルダ作成: $EdgeDir" -ForegroundColor Green
    }

    # 既存ファイルを退避
    if (Test-Path -Path $EdgeBookmarks) {
        $EdgeBak = "$EdgeBookmarks.bak-$DateSuffix"
        Copy-Item -Path $EdgeBookmarks -Destination $EdgeBak -Force
        Write-Host "退避: $EdgeBak" -ForegroundColor Gray
    }

    # 復元
    Copy-Item -Path $EdgeBackup -Destination $EdgeBookmarks -Force
    Write-Host "OK: $EdgeBookmarks" -ForegroundColor Green
}
else {
    Write-Host "Edge バックアップが見つかりません: $EdgeBackup" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " インポート完了" -ForegroundColor Green
Write-Host " ブラウザを起動して確認してください" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan

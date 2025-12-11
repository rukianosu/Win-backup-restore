<#
.SYNOPSIS
    Chrome / Edge のブックマークをエクスポート（バックアップ）

.DESCRIPTION
    Bookmarks ファイルを指定フォルダにコピーする
    ブラウザは事前に閉じておくこと
#>

# ブックマークファイルのパス（固定）
$ChromeBookmarks = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks"
$EdgeBookmarks = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"

# バックアップ先フォルダを入力
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " ブックマーク エクスポート" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "※ ブラウザを閉じてから実行してください" -ForegroundColor Yellow
Write-Host ""

$BackupRoot = Read-Host "バックアップを保存するフォルダを入力してください"

if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    Write-Host "フォルダが指定されていません。終了します。" -ForegroundColor Red
    exit 1
}

# 日付サブフォルダを作成
$DateFolder = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupPath = Join-Path -Path $BackupRoot -ChildPath $DateFolder

# フォルダ作成
if (-not (Test-Path -Path $BackupPath)) {
    New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
    Write-Host "フォルダ作成: $BackupPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "--- Chrome ---" -ForegroundColor Cyan

# Chrome Bookmarks コピー
if (Test-Path -Path $ChromeBookmarks) {
    $ChromeDest = Join-Path -Path $BackupPath -ChildPath "Chrome_Bookmarks"
    Copy-Item -Path $ChromeBookmarks -Destination $ChromeDest -Force
    Write-Host "OK: $ChromeDest" -ForegroundColor Green
}
else {
    Write-Host "Chrome Bookmarks が見つかりません: $ChromeBookmarks" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- Edge ---" -ForegroundColor Cyan

# Edge Bookmarks コピー
if (Test-Path -Path $EdgeBookmarks) {
    $EdgeDest = Join-Path -Path $BackupPath -ChildPath "Edge_Bookmarks"
    Copy-Item -Path $EdgeBookmarks -Destination $EdgeDest -Force
    Write-Host "OK: $EdgeDest" -ForegroundColor Green
}
else {
    Write-Host "Edge Bookmarks が見つかりません: $EdgeBookmarks" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " エクスポート完了" -ForegroundColor Green
Write-Host " 保存先: $BackupPath" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan

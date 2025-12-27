@echo off
chcp 65001 >nul
title ユーザーデータ 復元

:: 管理者権限で再起動
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 管理者権限で再起動します...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: スクリプトのあるフォルダに移動
cd /d "%~dp0"

:: PowerShellスクリプトを実行
powershell -ExecutionPolicy Bypass -File ".\Main-Restore.ps1"

pause

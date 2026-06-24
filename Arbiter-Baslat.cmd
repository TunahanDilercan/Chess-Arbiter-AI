@echo off
REM Cift tikla calistir: Arbiter AI tum stack'i baslatir.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-arbiter.ps1"

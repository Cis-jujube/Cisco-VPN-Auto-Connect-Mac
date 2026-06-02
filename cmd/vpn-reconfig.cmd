@echo off
@REM vpn-reconfig: Clear all config and re-run full setup
@REM Usage: vpn-reconfig
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Reconfigure

@echo off
@REM vpn-setup: Save or update VPN credentials (legacy single-config)
@REM Usage: vpn-setup
@REM Tip: prefer 'vpn-add' for multi-profile support
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -SaveCredentials

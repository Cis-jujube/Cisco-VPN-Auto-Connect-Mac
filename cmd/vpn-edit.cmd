@echo off
@REM vpn-edit: Edit existing VPN profile settings
@REM Usage: vpn-edit dku
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Edit %1

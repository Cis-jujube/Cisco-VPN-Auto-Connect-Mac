@echo off
@REM vpn-status: Show VPN connection status (checks 10.x.x.x IP)
@REM Usage: vpn-status
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Status

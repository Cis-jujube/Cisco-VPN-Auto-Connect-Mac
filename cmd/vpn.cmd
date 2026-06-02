@echo off
@REM vpn: List all available VPN commands
@REM Usage: vpn
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -List

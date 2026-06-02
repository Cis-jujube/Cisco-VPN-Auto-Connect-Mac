@echo off
@REM vpn-rm: Remove a VPN profile
@REM Usage: vpn-rm old-config
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Rm %1

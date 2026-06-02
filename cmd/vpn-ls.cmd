@echo off
@REM vpn-ls: List all VPN profiles
@REM Usage: vpn-ls
@REM Shows profile name, server address, * marks active profile
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Ls

@echo off
@REM vpn-use: Switch active VPN profile
@REM Usage: vpn-use dku
@REM        vpn-use company
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Use %1

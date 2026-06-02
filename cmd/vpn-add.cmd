@echo off
@REM vpn-add: Add a new VPN profile
@REM Usage: vpn-add
@REM   Prompts for: name, server, group, port, protocol, username, password
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Add

@echo off
@REM vpn-totp: Save DUO TOTP secret for fully automatic login
@REM Usage: vpn-totp
@REM Get secret: use 'qrgui' to decode DUO QR code, copy the Secret field
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -SaveTOTP

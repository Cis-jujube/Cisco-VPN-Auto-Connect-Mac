@echo off
@REM vpn-connect: Connect to VPN with DUO 2FA
@REM Usage: vpn-connect
@REM        vpn-connect push        (default, phone notification)
@REM        vpn-connect phone       (call verification)
@REM        vpn-connect sms         (SMS code)
@REM        vpn-connect passcode    (auto TOTP, fully automatic)
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Connect %*

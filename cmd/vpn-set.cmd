@echo off
@REM vpn-set: Quick-change a single VPN setting
@REM Usage: vpn-set server portal.dukekunshan.edu.cn
@REM        vpn-set port 8443
@REM        vpn-set protocol ipsec
@REM        vpn-set duo passcode
@REM        vpn-set user newuser
@REM Keys: server, group, port, protocol, user, duo
powershell -ExecutionPolicy Bypass -File "%~dp0..\vpn-auto-connect.ps1" -Set %1 -SetValue %2

@echo off
@REM vpn-timing: Profile VPN connect step timings (mirror mode)
@REM Usage: vpn-timing
@REM        vpn-timing -Preset dku -DuoMethod push
@REM        vpn-timing -Runs 3
@powershell -ExecutionPolicy Bypass -File "%~dp0..\tests\Measure-VpnConnectTiming.ps1" %*

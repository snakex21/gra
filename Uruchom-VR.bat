@echo off
setlocal
pushd "%~dp0"
python tools\run_vr.py %*
set "GAME_EXIT=%ERRORLEVEL%"
popd
exit /b %GAME_EXIT%

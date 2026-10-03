@echo off
setlocal
pushd "%~dp0"
python tools\run_local.py godot %*
set "GAME_EXIT=%ERRORLEVEL%"
popd
exit /b %GAME_EXIT%

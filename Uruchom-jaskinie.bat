@echo off
setlocal
pushd "%~dp0"
python tools\run_local.py godot scenes/cave_arena.tscn %*
set "GAME_EXIT=%ERRORLEVEL%"
popd
exit /b %GAME_EXIT%

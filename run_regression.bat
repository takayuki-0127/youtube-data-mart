@echo off
chcp 65001 > nul
cd /d %~dp0
set PYTHONUTF8=1
set PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
"%PY%" notebooks\e_03_regression.py > regression.log 2>&1
echo === exit %errorlevel% === >> regression.log

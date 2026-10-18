@echo off
chcp 65001 > nul
cd /d %~dp0
set PYTHONUTF8=1
set PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
"%PY%" src\load_regression_to_mart.py > regression_to_mart.log 2>&1
echo === exit %errorlevel% === >> regression_to_mart.log

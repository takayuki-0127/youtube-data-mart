@echo off
chcp 65001 > nul
cd /d %~dp0
set PYTHONUTF8=1
set PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
"%PY%" -m pip install -q matplotlib > regression_check.log 2>&1
"%PY%" notebooks\e_04_regression_check.py >> regression_check.log 2>&1
echo === exit %errorlevel% === >> regression_check.log

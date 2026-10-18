@echo off
chcp 65001 > nul
cd /d %~dp0
set PYTHONUTF8=1
set PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
"%PY%" src\run_sql.py sql\02_create_mart.sql sql\03_load_mart.sql sql\04_views.sql > mart.log 2>&1
echo === features === >> mart.log
"%PY%" notebooks\e_02_read_features.py >> mart.log 2>&1
echo === exit %errorlevel% === >> mart.log

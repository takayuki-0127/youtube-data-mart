@echo off
chcp 65001 > nul
cd /d %~dp0
set PYTHONUTF8=1
set PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
rem 2回目以降：表は作り直さず、stg → mart の読み込みとビューだけ流す
"%PY%" src\run_sql.py sql\03_load_mart.sql sql\04_views.sql > mart_reload.log 2>&1
echo === exit %errorlevel% === >> mart_reload.log

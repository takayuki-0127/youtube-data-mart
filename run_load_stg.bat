@echo off
chcp 65001 > nul
cd /d %~dp0
set PYTHONUTF8=1
set LOG=%~dp0load.log
echo === start %date% %time% === > "%LOG%"
set PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if not exist "%PY%" (
  echo === winget install Python 3.12 === >> "%LOG%"
  winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements >> "%LOG%" 2>&1
)
if not exist "%PY%" ( echo PYTHON NOT FOUND after install >> "%LOG%" & exit /b 1 )
"%PY%" --version >> "%LOG%" 2>&1
echo === pip install === >> "%LOG%"
"%PY%" -m pip install --upgrade pip -q >> "%LOG%" 2>&1
"%PY%" -m pip install -q -r requirements.txt >> "%LOG%" 2>&1
echo === load_stg === >> "%LOG%"
"%PY%" src\load_stg.py >> "%LOG%" 2>&1
echo === exit code %errorlevel% === >> "%LOG%"

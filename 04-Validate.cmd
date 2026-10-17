@echo off
setlocal
cd /d "%~dp0"
set "PYTHONDONTWRITEBYTECODE=1"

where py >nul 2>&1
if not errorlevel 1 (
    py -3 -B "%~dp0Tools\validate_local.py" %*
) else (
    where python >nul 2>&1
    if not errorlevel 1 (
        python -B "%~dp0Tools\validate_local.py" %*
    ) else (
        echo ERROR: Python 3 was not found. Install Python 3 or enable the Windows py launcher.
        pause
        exit /b 1
    )
)
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
    echo Local validation finished with no detected failures.
) else (
    echo Local validation failed. Review the messages above.
)
echo.
pause
exit /b %RESULT%

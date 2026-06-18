@echo off
setlocal
cd /d "%~dp0\..\.."

if not exist samples\hello (
    echo ERROR: samples\hello not found.
    echo Compile the demo first, for example:
    echo   cl samples\hello.c /Fe:samples\hello.exe
    echo   copy samples\hello.exe samples\hello
    echo or with MinGW:
    echo   gcc -o samples\hello samples\hello.c
    exit /b 1
)

if not exist .env (
    copy /Y .env.example .env >nul
)

echo Stopping running services ...
docker compose down

echo Importing samples\hello into project hello_demo ...
docker compose --profile import run --rm ghidrasql-import
if errorlevel 1 exit /b 1

echo Starting services ...
docker compose up -d
if errorlevel 1 exit /b 1

echo Demo import complete. SQL endpoint: http://127.0.0.1:8081/query

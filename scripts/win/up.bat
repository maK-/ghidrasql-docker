@echo off
setlocal
cd /d "%~dp0\..\.."

if not exist .env (
    copy /Y .env.example .env >nul
    echo Created .env from .env.example
)

docker compose up -d
if errorlevel 1 exit /b 1

echo Services started. LibGhidraHost: http://127.0.0.1:18080  SQL: http://127.0.0.1:8081

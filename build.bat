@echo off
setlocal
cd /d "%~dp0"

if /i "%~1"=="--local" (
    if "%~2"=="" (
        echo ERROR: Usage: build.bat --local \path\to\ghidra_12.0.4_PUBLIC
        exit /b 1
    )
    if not exist "%~2\support\analyzeHeadless" (
        echo ERROR: Not a Ghidra distribution: %~2
        exit /b 1
    )
    echo Building ghidrasql-ai-base:latest from local tree: %~2
    docker build -f Dockerfile.base.local --build-context ghidra="%~2" -t ghidrasql-ai-base:latest .
    if errorlevel 1 exit /b 1
    goto build_app
)

echo Building ghidrasql-ai-base:latest (download Ghidra 12.0.4) ...
docker build -f Dockerfile.base -t ghidrasql-ai-base:latest .
if errorlevel 1 exit /b 1

:build_app
echo Building ghidrasql-ai:latest ...
docker build -f Dockerfile -t ghidrasql-ai:latest .
if errorlevel 1 exit /b 1

where gcc >nul 2>&1
if not errorlevel 1 (
    if exist samples\hello.c (
        echo Compiling samples\hello ...
        gcc -o samples\hello samples\hello.c
    )
) else (
    echo WARNING: gcc not found; samples\hello not built
)

echo Done. Images: ghidrasql-ai-base:latest, ghidrasql-ai:latest

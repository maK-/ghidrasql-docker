@echo off
setlocal

curl -sS -X POST http://127.0.0.1:8081/query --data "SELECT COUNT(*) AS funcs FROM funcs"
echo.

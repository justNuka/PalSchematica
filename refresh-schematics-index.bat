@echo off
setlocal
cd /d "%~dp0Schematics"

(
    echo # PalSchematica library index - generated automatically
    for %%F in (*.palschem) do echo %%F
) > index.txt

echo.
echo PalSchematica index refreshed:
type index.txt
echo.
pause

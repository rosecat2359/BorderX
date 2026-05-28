@echo off
REM BorderX build script — Windows + Linux
cd /d "%~dp0server"

echo === Building for Windows ===
go build -o borderx-panel.exe ./cmd/panel/
echo Windows: borderx-panel.exe (%errorlevel%)

echo === Building for Linux ===
set GOOS=linux
set GOARCH=amd64
go build -o borderx-panel ./cmd/panel/
echo Linux: borderx-panel (%errorlevel%)

echo.
echo Done. Binaries in server/
dir borderx-panel* | findstr borderx

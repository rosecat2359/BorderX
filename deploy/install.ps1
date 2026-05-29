$ErrorActionPreference = "Stop"
$InstallDir = "C:\Program Files\BorderX"
$DataDir = "$env:ProgramData\BorderX"

Write-Host "=== BorderX Panel v2.0 安装 ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $InstallDir, $DataDir | Out-Null

$Url = "https://github.com/borderx/panel/releases/latest/download/borderx-panel-windows-amd64.exe"
$OutPath = "$InstallDir\borderx-panel.exe"
Write-Host "下载: $Url"
Invoke-WebRequest -Uri $Url -OutFile $OutPath

# Register Windows Service
New-Service -Name "BorderXPanel" `
  -BinaryPathName "`"$OutPath`" --data-dir `"$DataDir`"" `
  -DisplayName "BorderX Panel" `
  -StartupType Automatic `
  -ErrorAction SilentlyContinue

Start-Service BorderXPanel -ErrorAction SilentlyContinue

Write-Host "=== 安装完成 ===" -ForegroundColor Green
Write-Host "面板: http://localhost:8080"
Write-Host "首次启动需要设置管理员密码"

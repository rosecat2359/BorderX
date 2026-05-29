$ErrorActionPreference = "Continue"

Write-Host "=== BorderX Panel 卸载 ===" -ForegroundColor Cyan
Write-Host ""

# Stop and remove service
$svc = Get-Service -Name "BorderXPanel" -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service "BorderXPanel" -Force
    sc.exe delete "BorderXPanel" | Out-Null
    Write-Host "[OK] Windows 服务已删除"
}

# Remove binary
$binPath = "C:\Program Files\BorderX\borderx-panel.exe"
if (Test-Path $binPath) {
    Remove-Item $binPath -Force
    Write-Host "[OK] 二进制文件已删除"
}
$installDir = "C:\Program Files\BorderX"
if ((Get-ChildItem $installDir -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
    Remove-Item $installDir -Force
}

# Ask about data
$dataDir = "$env:ProgramData\BorderX"
if (Test-Path $dataDir) {
    $yn = Read-Host "是否删除数据目录 $dataDir？(包括数据库) [y/N]"
    if ($yn -eq 'y' -or $yn -eq 'Y') {
        Remove-Item $dataDir -Recurse -Force
        Write-Host "[OK] 数据目录已删除"
    } else {
        Write-Host "[OK] 数据目录已保留: $dataDir"
    }
}

Write-Host ""
Write-Host "=== 卸载完成 ===" -ForegroundColor Green

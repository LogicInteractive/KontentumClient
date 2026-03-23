Set-Location "bin"

Write-Host "Testing --install command..." -ForegroundColor Cyan
Write-Host ""

$process = Start-Process -FilePath ".\KontentumClient.exe" -ArgumentList "--install" -Wait -PassThru -NoNewWindow
Write-Host "Exit code: $($process.ExitCode)" -ForegroundColor Yellow
Write-Host ""

Write-Host "Checking registry..." -ForegroundColor Cyan
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regValue = Get-ItemProperty -Path $regPath -Name "KontentumClient" -ErrorAction SilentlyContinue

if ($regValue) {
    Write-Host "SUCCESS: Registry key exists" -ForegroundColor Green
    Write-Host "Value: $($regValue.KontentumClient)" -ForegroundColor Green
} else {
    Write-Host "FAILED: Registry key not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "Testing --uninstall command..." -ForegroundColor Cyan
Write-Host ""

$process2 = Start-Process -FilePath ".\KontentumClient.exe" -ArgumentList "--uninstall" -Wait -PassThru -NoNewWindow
Write-Host "Exit code: $($process2.ExitCode)" -ForegroundColor Yellow
Write-Host ""

Write-Host "Verifying removal..." -ForegroundColor Cyan
$regValue2 = Get-ItemProperty -Path $regPath -Name "KontentumClient" -ErrorAction SilentlyContinue

if ($regValue2) {
    Write-Host "FAILED: Registry key still exists" -ForegroundColor Red
} else {
    Write-Host "SUCCESS: Registry key removed" -ForegroundColor Green
}

Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

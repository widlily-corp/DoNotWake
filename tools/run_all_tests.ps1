# =============================================================================
# Do Not Wake — Скрипт пакетного запуска автотестов
# =============================================================================
# Запуск всех тестов проекта (tests/test_*.gd) в headless-режиме через консоль Godot.
# Не глотает вывод (стримит в реальном времени через Out-Host).
# Печатает структурированную сводку PASS/FAIL по каждому тесту и возвращает
# итоговый код выхода процесса (0 при успехе всех тестов, 1 при наличии ошибок).
#
# Использование:
#   powershell -File tools/run_all_tests.ps1
#   powershell -File tools/run_all_tests.ps1 -Filter "test_data_integrity.gd"
# =============================================================================

param (
    [string]$GodotPath = "GODOT_BIN",
    [string]$ProjectPath = "",
    [string]$Filter = "test_*.gd"
)

# Определение пути к проекту
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = (Resolve-Path "$PSScriptRoot\..").Path
} else {
    $ProjectPath = (Resolve-Path $ProjectPath).Path
}

# Проверка наличия исполняемого файла Godot
if (-not (Test-Path $GodotPath)) {
    Write-Error "CRITICAL: Godot executable not found at: '$GodotPath'"
    exit 1
}

# Поиск всех файлов тестов
$testsDir = Join-Path $ProjectPath "tests"
if (-not (Test-Path $testsDir)) {
    Write-Error "CRITICAL: Tests directory not found at: '$testsDir'"
    exit 1
}

$testFiles = Get-ChildItem -Path $testsDir -Filter $Filter | Sort-Object Name

if ($testFiles.Count -eq 0) {
    Write-Warning "No test files matching '$Filter' found in '$testsDir'."
    exit 0
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " DO NOT WAKE · TEST RUNNER" -ForegroundColor Cyan
Write-Host " Project: $ProjectPath"
Write-Host " Godot:   $GodotPath"
Write-Host " Tests:   $($testFiles.Count) file(s) found"
Write-Host " Date:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$results = @()
$failedCount = 0
$passedCount = 0
$totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($t in $testFiles) {
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host ">>> RUNNING: tests/$($t.Name)" -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Запуск теста через консольный Godot headless
    # 2>&1 | Out-Host обеспечивает вывод логов и ошибок движка в реальном времени
    & $GodotPath --headless --path $ProjectPath -s ("tests/" + $t.Name) 2>&1 | Out-Host
    $exitCode = $LASTEXITCODE

    $sw.Stop()
    $durationSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    $status = "PASS"
    if ($exitCode -ne 0) {
        $status = "FAIL"
        $failedCount++
        Write-Host ">>> RESULT: [FAIL] tests/$($t.Name) (ExitCode: $exitCode, Time: ${durationSec}s)" -ForegroundColor Red
    } else {
        $passedCount++
        Write-Host ">>> RESULT: [PASS] tests/$($t.Name) (Time: ${durationSec}s)" -ForegroundColor Green
    }
    Write-Host ""

    $results += [PSCustomObject]@{
        TestName = $t.Name
        Status   = $status
        ExitCode = $exitCode
        Duration = "${durationSec}s"
    }
}

$totalStopwatch.Stop()
$totalSec = [math]::Round($totalStopwatch.Elapsed.TotalSeconds, 2)

# =============================================================================
# ИТОГОВАЯ СВОДКА
# =============================================================================
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " TEST RUN SUMMARY" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Property TestName, Status, ExitCode, Duration | Out-Host

Write-Host "Total Tests: $($testFiles.Count)" -ForegroundColor White
Write-Host "Passed:      $passedCount" -ForegroundColor Green
Write-Host "Failed:      $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })
Write-Host "Total Time:  ${totalSec}s" -ForegroundColor White

if ($results | Where-Object { $_.TestName -eq "test_robot_interactivity.gd" -and $_.Status -eq "FAIL" }) {
    Write-Host ""
    Write-Host "NOTE: 'test_robot_interactivity.gd' is a known baseline failure (4/48 proximity awareness)" -ForegroundColor DarkYellow
    Write-Host "      per контракт данных §8 and docs/architecture.md §4. It does not block этап 1 contracts delivery." -ForegroundColor DarkYellow
}

Write-Host "=================================================================" -ForegroundColor Cyan

if ($failedCount -gt 0) {
    Write-Host "OVERALL STATUS: FAILED ($failedCount test(s) failed)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "OVERALL STATUS: PASSED (All tests succeeded)" -ForegroundColor Green
    exit 0
}

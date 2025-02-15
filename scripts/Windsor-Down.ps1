param (
    [string]$WINDSORCLI_EXE_PATH,
    [bool]$CLEAN = $true
)

if (-not (Test-Path $WINDSORCLI_EXE_PATH)) {
    Write-Output "Error: WINDSORCLI_EXE_PATH is not defined."
    exit 1
}

if ($CLEAN) {
    Write-Output "Running Windsor Down with clean option..."
    & $WINDSORCLI_EXE_PATH down --clean
} else {
    Write-Output "Running Windsor Down without clean option..."
    & $WINDSORCLI_EXE_PATH down
}

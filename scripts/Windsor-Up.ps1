param (
    [string]$WINDSORCLI_EXE_PATH,
    [string]$GITHUB_WORKSPACE
)

# Set WINDSOR_PROJECT_ROOT
[System.Environment]::SetEnvironmentVariable('WINDSOR_PROJECT_ROOT', $GITHUB_WORKSPACE, [System.EnvironmentVariableTarget]::Process)

# Windsor Init
& $WINDSORCLI_EXE_PATH init local

# Disable DNS
Write-Output "Disabling DNS in windsor.yaml"
yq eval '.contexts.local.dns.enabled = false' -i windsor.yaml
Get-Content windsor.yaml

# Windsor Up
& $WINDSORCLI_EXE_PATH context get
& $WINDSORCLI_EXE_PATH up --install --verbose
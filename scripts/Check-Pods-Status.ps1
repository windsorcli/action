# PowerShell script to check the status of Kubernetes pods

param (
    [string]$WINDSORCLI_EXE_PATH
)

if (-not ${WINDSORCLI_EXE_PATH}) {
    Write-Host "Usage: .\Check-Pods-Status.ps1 -WINDSORCLI_EXE_PATH <WINDSORCLI_EXE_PATH>"
    exit 1
}

# Debug: Print the Windsor CLI path
Write-Host "Using Windsor CLI at path: $WINDSORCLI_EXE_PATH"

# Fetch all pods in all namespaces in JSON format
try {
    & "$WINDSORCLI_EXE_PATH" exec -- kubectl get pods -A -o json 2>$null > pods.json
} catch {
    Write-Host "Error executing Windsor CLI command: $_"
    exit 1
}
$pods_json = Get-Content -Path "pods.json"

# Check if the kubectl command was successful
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to access the Kubernetes cluster. Please check your connection and permissions."
    exit 1
}

# Check if the JSON output is empty
if (-not $pods_json) {
    Write-Host "No JSON output received. Please check if the Kubernetes cluster is accessible and has pods."
    exit 1
}

# Check if the JSON output is valid
try {
    $pods_data = $pods_json | ConvertFrom-Json
} catch {
    Write-Host "Invalid JSON output"
    exit 1
}

# Use PowerShell to parse the JSON and extract relevant information
# Format: NAMESPACE POD_NAME STATUS
$pod_summary = $pods_data.items | ForEach-Object {
    "$($_.metadata.namespace) $($_.metadata.name) $($_.status.phase)"
}

# Initialize counters
$running_count = 0
$non_running_count = 0

# Print the header with fixed-width columns
"{0,-20} {1,-50} {2,-10}" -f "NAMESPACE", "POD_NAME", "STATUS"

# Process each line of the pod summary
foreach ($line in $pod_summary) {
    $fields = $line -split ' '
    $namespace = $fields[0]
    $pod_name = $fields[1]
    $status = $fields[2]
    
    # Print all pods with their status using fixed-width columns
    "{0,-20} {1,-50} {2,-10}" -f $namespace, $pod_name, $status
    
    if ($status -ne "Running") {
        $non_running_count++
    } else {
        $running_count++
    }
}

# Print summary
Write-Host "`nSummary:"
Write-Host "Running pods: $running_count"
Write-Host "Non-running pods: $non_running_count"

# Exit with success if no non-running pods, otherwise exit with failure
if ($non_running_count -eq 0) {
    exit 0
} else {
    exit 1
}

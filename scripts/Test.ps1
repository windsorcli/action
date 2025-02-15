param (
    [string]$WINDSORCLI_EXE_PATH,
    [string]$WINDSORCLI_VERSION,
    [string]$WINDSORCLI_ARCH,
    [string]$GITHUB_WORKSPACE,
    [string]$RUNNER_OS,
    [string]$USE_DOCKER,
    [string]$WINDSOR_TEST_CONFIG_FILE
)

$DEBUG = $true

# git clone https://github.com/bats-core/bats-core.git
# cd bats-core
# ./install.sh ../bin

if ($DEBUG) {
    Write-Host "WINDSORCLI_EXE_PATH: $WINDSORCLI_EXE_PATH"
    Write-Host "WINDSORCLI_VERSION: $WINDSORCLI_VERSION"
    Write-Host "WINDSORCLI_ARCH: $WINDSORCLI_ARCH"
    Write-Host "GITHUB_WORKSPACE: $GITHUB_WORKSPACE"
    Write-Host "RUNNER_OS: $RUNNER_OS"
    Write-Host "USE_DOCKER: $USE_DOCKER"
    if (Test-Path -Path $WINDSORCLI_EXE_PATH) {
        Write-Host "Windsor CLI found at $WINDSORCLI_EXE_PATH"
    } else {
        Write-Host "Windsor CLI not found at $WINDSORCLI_EXE_PATH"
        exit 1
    }    
}

exit 0

# Build Docker image if USE_DOCKER is true
if ($USE_DOCKER) {

    # Check if Docker is installed
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        Write-Host "Docker is not installed. Exiting."
        exit 1
    }

    Write-Output "Get Docker version..."
    docker version

    Write-Output "Building Docker image..."

    $dockerPath = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
    & $dockerPath build -t windsortest:latest --build-arg windsorcli_version="$WINDSORCLI_VERSION" --build-arg windsorcli_arch="$WINDSORCLI_ARCH" "$GITHUB_WORKSPACE\docker"
}

# Read the tests-list from the WINDSOR_TEST_CONFIG_FILE using yq
try {
    $tests_list_json = & yq eval -o=json "$WINDSOR_TEST_CONFIG_FILE"
    $tests_list = $tests_list_json | ConvertFrom-Json
} catch {
    Write-Host "Error reading or parsing YAML file with yq: $_"
    exit 1
}

Write-Host "========================================="
Write-Host "              STARTING TEST              "
Write-Host "========================================="

# Loop through each test entry in the tests-list
foreach ($row in $tests_list.'tests-list') {
    $path = $row.path
    $type = if ($null -eq $row.type) { 'shell' } else { $row.type }
    $os_list = $row.os

    # Check if the current OS is supported for the test
    if (-not $os_list -or $os_list -contains $RUNNER_OS) {
        try {
            Write-Host "Running $type tests with path = $path"

            if ($USE_DOCKER) {
                switch ($type) {
                    'shell' {
                        docker run --rm -i `
                            -v "${GITHUB_WORKSPACE}:/workspace" `
                            -w /workspace `
                            windsortest:latest `
                            bash -c "dos2unix '$path' && bash '$path'"
                    }
                    'bats' {
                        docker run --rm -i `
                            -v "${GITHUB_WORKSPACE}:/workspace" `
                            -w /workspace `
                            windsortest:latest `
                            bash -c "bats '$path'"
                    }
                    default {
                        Write-Host "Unknown test type: $type"
                    }
                }
            } else {
                switch ($type) {
                    'shell' {
                        & bash -c "dos2unix '$path'; bash '$path'"
                    }
                    'bats' {
                        Write-Host "Skipping: bats '$path'"
                    }
                    default {
                        Write-Host "Unknown test type: $type"
                    }
                }
            }
        } catch {
            Write-Host "Error running command for $type tests: $_"
        }
    } else {
        Write-Host "Skipping $type test at $path for OS $RUNNER_OS"
    }
}

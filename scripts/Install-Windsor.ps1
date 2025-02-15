# Install-Windsor.ps1

# Define input parameters
param (
    [string]$WINDSORCLI_INSTALL_FOLDER,
    [string]$USE_RELEASE,
    [string]$HOST_OS,
    [string]$HOST_ARCH,
    [string]$WINDSORCLI_VERSION,
    [string]$WINDSORCLI_BRANCH
)

Write-Output "WINDSORCLI_INSTALL_FOLDER: $WINDSORCLI_INSTALL_FOLDER"
Write-Output "USE_RELEASE: $USE_RELEASE"
Write-Output "HOST_OS: $HOST_OS"
Write-Output "HOST_ARCH: $HOST_ARCH"
Write-Output "WINDSORCLI_VERSION: $WINDSORCLI_VERSION"
Write-Output "WINDSORCLI_BRANCH: $WINDSORCLI_BRANCH"

# Convert $HOST_OS
switch ($HOST_OS) {
  "Windows" {
    $TMP_HOST_OS = "windows"
  }
}

# Convert $HOST_ARCH
switch ($HOST_ARCH) {
  "ARM64" {
    $TMP_HOST_ARCH = "arm64"
  }
  "X64" {
    $TMP_HOST_ARCH = "amd64"
  }
  default {
    Write-Output "Unsupported HOST_ARCH: $HOST_ARCH"
    exit 1
  }
}

# Create bin directory
Write-Output "Creating directory on Windows: $WINDSORCLI_INSTALL_FOLDER"
try {
    New-Item -Path $WINDSORCLI_INSTALL_FOLDER -ItemType Directory -Force -ErrorAction Stop
} catch {
    Write-Output "Failed to create directory: $WINDSORCLI_INSTALL_FOLDER"
    exit 1
}

# Install Windsor CLI
if ($USE_RELEASE -eq "true") {
    Write-Output "Installing Windsor CLI on Windows from release ($WINDSORCLI_VERSION)..."
    $numeric_version = $WINDSORCLI_VERSION.TrimStart('v')
    $url = "https://github.com/windsorcli/cli/releases/download/$WINDSORCLI_VERSION/windsor_${numeric_version}_${TMP_HOST_OS}_${TMP_HOST_ARCH}.tar.gz"
    $outputFile = "windsor_${numeric_version}_${TMP_HOST_OS}_${TMP_HOST_ARCH}.tar.gz"
    
    # Download the release
    try {
        Invoke-WebRequest -Uri $url -Headers @{"Accept"="application/octet-stream"} -OutFile $outputFile -ErrorAction Stop
    } catch {
        Write-Output "Failed to download Windsor CLI from $url"
        exit 1
    }
    
    # Extract the tar.gz file
    try {
        tar -xzf $outputFile -C $WINDSORCLI_INSTALL_FOLDER
    } catch {
        Write-Output "Failed to extract $outputFile"
        exit 1
    }
    
    # Verify installation
    $windsorExePath = Join-Path -Path $WINDSORCLI_INSTALL_FOLDER -ChildPath "windsor.exe"
    if (Test-Path -Path $windsorExePath) {
        Write-Output "Windsor CLI installed at $windsorExePath"
    } else {
        Write-Output "Failed to install Windsor CLI at $windsorExePath"
        exit 1
    }
} else {
    Write-Output "Installing Windsor CLI on Windows from branch ($WINDSORCLI_BRANCH)..."
    try {
        git clone --branch $WINDSORCLI_BRANCH https://github.com/windsorcli/cli.git
    } catch {
        Write-Output "Failed to clone the repository from branch $WINDSORCLI_BRANCH"
        exit 1
    }
    
    try {
        Set-Location -Path "cli" -ErrorAction Stop
    } catch {
        Write-Output "Failed to navigate to the Windsor CLI directory"
        exit 1
    }
    
    try {
        # Ensure the correct path to the main.go file
        go build -o "$WINDSORCLI_INSTALL_FOLDER\windsor.exe" ./cmd/windsor/main.go
    } catch {
        Write-Output "Failed to build the Windsor CLI"
        exit 1
    }
}

Write-Output "Installation complete."

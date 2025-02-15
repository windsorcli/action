#!/bin/bash
WINDSORCLI_EXE_PATH=$1 
WINDSORCLI_VERSION=$2 
WINDSORCLI_ARCH=$3
GITHUB_WORKSPACE=$4
RUNNER_OS=$5
USE_DOCKER=$6
WINDSOR_TEST_CONFIG_FILE=$7
DEBUG=false

if [ "$#" -ne 7 ]; then
  echo "Usage: $0 <WINDSORCLI_EXE_PATH> <WINDSORCLI_VERSION> <WINDSORCLI_ARCH> <GITHUB_WORKSPACE> <RUNNER_OS> <USE_DOCKER> <WINDSOR_TEST_CONFIG_FILE>"
  exit 1
fi

if [ "$DEBUG" = true ]; then
    echo ""
    echo "WINDSORCLI_VERSION: $WINDSORCLI_VERSION"
    echo "WINDSORCLI_ARCH: $WINDSORCLI_ARCH"
    echo "WINDSORCLI_EXE_PATH: $WINDSORCLI_EXE_PATH"
    echo "GITHUB_WORKSPACE: $GITHUB_WORKSPACE"
    echo "RUNNER_OS: $RUNNER_OS"
    echo "USE_DOCKER: $USE_DOCKER"
    echo "WINDSOR_TEST_CONFIG_FILE: $WINDSOR_TEST_CONFIG_FILE"
    echo ""
fi

# Detect OS
OS="$(uname -s)"

# Array to track installed shells for cleanup
INSTALLED_SHELLS=()

install_brew() {
    if [[ "$OS" == "Darwin" ]]; then
        if ! command -v brew &> /dev/null; then
            echo "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # echo "/opt/homebrew/bin" >> $GITHUB_PATH
            # export PATH="/opt/homebrew/bin:$PATH"
        fi
    fi
}

# Function to install a shell if not present
install_shell() {
    local shell_name="$1"
    local ubuntu_pkg="$2"
    local macos_pkg="$3"

    if ! command -v "$shell_name" &> /dev/null; then
        echo "Installing $shell_name..."
        if [[ "$OS" == "Linux" ]]; then
            sudo apt-get update && sudo apt-get install -y "$ubuntu_pkg"
        elif [[ "$OS" == "Darwin" ]]; then
            /opt/homebrew/bin/brew install "$macos_pkg"
        fi
        INSTALLED_SHELLS+=("$shell_name") # Track installed shells for removal
    else
        echo "$shell_name is already installed."
    fi
}

# Function to remove installed shells
cleanup_shells() {
    echo "Cleaning up installed shells..."
    for shell in "${INSTALLED_SHELLS[@]}"; do
        echo "Removing $shell..."
        if [[ "$OS" == "Linux" ]]; then
            sudo apt-get remove --purge -y "$shell"
        elif [[ "$OS" == "Darwin" ]]; then
            /opt/homebrew/bin/brew uninstall "$shell"
        fi
    done
    echo "Cleanup complete."
}

# Install Homebrew
install_brew


# Function to run a command in a shell
run_in_shell() {
    local shell_cmd="$1"
    local check_shell_var="$2"
    
    echo "Switching to and verifying $shell_cmd shell"

    if ! command -v "$shell_cmd" &> /dev/null; then
        echo "Error: $shell_cmd is not installed or not executable."
        return 1
    fi

    # Capture the output and print it
    output=$($shell_cmd -c "echo 'Switched to $shell_cmd'; echo 'Current shell: $check_shell_var'")
    echo "$output" || return 1
}

# # PowerShell uses a different syntax
# if command -v pwsh &> /dev/null; then
#     echo "Switching to and verifying PowerShell shell"
#     pwsh -Command 'Write-Host "Switched to PowerShell"; Write-Host "Current shell: $($PSVersionTable.PSVersion)"'
# else
#     echo "PowerShell is not installed."
# fi


# rm -rf \
#   /opt/homebrew/etc/fish \
#   /opt/homebrew/etc/fish/completions \
#   /opt/homebrew/etc/fish/conf.d \
#   /opt/homebrew/etc/fish/config.fish \
#   /opt/homebrew/etc/fish/functions

# Build Docker image if USE_DOCKER is true
if [ "$USE_DOCKER" = true ]; then
    numeric_version="${WINDSORCLI_VERSION//v/}"
    docker build -t windsortest:latest --build-arg windsorcli_version="$numeric_version" --build-arg windsorcli_arch="$WINDSORCLI_ARCH" ./docker
fi

# Read the tests-list from the WINDSOR_TEST_CONFIG_FILE
tests_list=$(yq e '.tests-list' "$WINDSOR_TEST_CONFIG_FILE")

echo "========================================="
echo "              STARTING TEST              "
echo "========================================="

# Loop through each test entry
for row in $(echo "${tests_list}" | yq e -o=json | jq -c '.[]'); do
    path=$(echo "$row" | jq -r '.path')
    type=$(echo "$row" | jq -r '.type // "shell"')
    os_list=$(echo "$row" | jq -r '.os | join(" ")')
    shell=$(echo "$row" | jq -r '.shell // "bash"')

    # Install necessary shells
    case "$shell" in
        "bash")
            install_shell "bash" "bash" "bash"
            ;;
        "zsh")
            install_shell "zsh" "zsh" "zsh"
            ;;
        "fish")
            install_shell "fish" "fish" "fish"
            ;;
        "pwsh")
            install_shell "pwsh" "powershell" "powershell"
            ;;
        "tcsh")
            install_shell "tcsh" "tcsh" "tcsh"
            ;;
        "elvish")
            install_shell "elvish" "elvish" "elvish"
            ;;
        *)
            echo "Unknown shell: $shell"
            ;;
    esac


    # Check if the current OS is supported for the test
    if [[ -z "$os_list" || "$os_list" == *"$RUNNER_OS"* ]]; then
        echo "Running ${type} tests using ${shell} shell at ${path}"

        if [ "$USE_DOCKER" = true ]; then
            case $type in
                shell)
                    docker run --rm -i \
                        -v "$GITHUB_WORKSPACE":/workspace \
                        -w /workspace \
                        windsortest:latest \
                        bash -c "bash ${path}"
                    ;;
                bats)
                    docker run --rm -i \
                        -v "$GITHUB_WORKSPACE":/workspace \
                        -w /workspace \
                        windsortest:latest \
                        bash -c "bats ${path}"
                    ;;
                *)
                    echo "Unknown test type: ${type}"
                    ;;
            esac
        else
            case $type in
                shell)
                    if ! run_in_shell "$shell" "${path}"; then
                        echo "Error: ${type} tests failed at ${path} using ${shell} shell"
                        exit 1
                    fi
                    ;;
                bats)
                    if ! command -v "$shell" &> /dev/null; then
                        echo "Error: $shell is not installed or not executable."
                        return 1
                    fi

                    echo "Switched to $shell"
                    if ! $shell -c "bats ${path}"; then
                        echo "Error: bats tests failed at ${path} using ${shell} shell"
                        return 1
                    fi
                    ;;
                *)
                    echo "Unknown test type: ${type}"
                    ;;
            esac
        fi
    else
        echo "Skipping ${type} test at ${path} for OS ${RUNNER_OS}"
    fi
done

# Cleanup installed shells
cleanup_shells

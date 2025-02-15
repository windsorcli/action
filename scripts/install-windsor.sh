#!/bin/bash

set -e

WINDSORCLI_INSTALL_FOLDER=$1
USE_RELEASE=$2
HOST_OS=$3
HOST_ARCH=$4
WINDSORCLI_VERSION=$5
WINDSORCLI_BRANCH=$6

# Check if the correct number of arguments is provided
if [ "$#" -ne 6 ]; then
  echo "Usage: $0 <WINDSORCLI_INSTALL_FOLDER> <USE_RELEASE> <HOST_OS> <HOST_ARCH> <WINDSORCLI_VERSION> <WINDSORCLI_BRANCH>"
  exit 1
fi


# Convert HOST_ARCH to TMP_ARCH
case "$HOST_ARCH" in
  "ARM64")
    TMP_HOST_ARCH="arm64"
    ;;
  "X64")
    TMP_HOST_ARCH="amd64"
    ;;
  *)
    echo "Unsupported HOST_ARCH: $HOST_ARCH"
    exit 1
    ;;
esac

# Convert HOST_OS to TMP_OS
case "$HOST_OS" in
  "Windows")
    TMP_HOST_OS="windows"
    ;;
  "Linux")
    TMP_HOST_OS="linux"
    ;;
  "macOS")
    TMP_HOST_OS="darwin"
    ;;
  *)
    echo "Unsupported HOST_OS: $HOST_OS"
    exit 1
    ;;
esac

numeric_version=${WINDSORCLI_VERSION#v}

LOCAL_FILE_NAME="windsor_${numeric_version}_${TMP_HOST_OS}_${TMP_HOST_ARCH}.tar.gz"
DOWNLOAD_FILE_NAME="https://github.com/windsorcli/cli/releases/download/${WINDSORCLI_VERSION}/${LOCAL_FILE_NAME}"

echo "Creating directory: $WINDSORCLI_INSTALL_FOLDER"
if ! command -v mkdir &> /dev/null; then
  echo "mkdir command not found. Please ensure it is installed and in your PATH."
  exit 1
fi
mkdir -p "$WINDSORCLI_INSTALL_FOLDER"

if [ "$USE_RELEASE" == "true" ]; then
  echo "Installing Windsor CLI using release (${WINDSORCLI_VERSION})..."
  curl -L -o "$LOCAL_FILE_NAME" "$DOWNLOAD_FILE_NAME"
  tar -xzf "$LOCAL_FILE_NAME" -C "$WINDSORCLI_INSTALL_FOLDER"
  chmod +x "$WINDSORCLI_INSTALL_FOLDER"/windsor
  rm -rf "$LOCAL_FILE_NAME"
else
  echo "Installing Windsor CLI from branch (${WINDSORCLI_BRANCH})..."
  if [ -z "$WINDSORCLI_BRANCH" ]; then
    echo "WINDSORCLI_BRANCH is not set."
    exit 1
  fi
  if ! git clone --branch "$WINDSORCLI_BRANCH" https://github.com/windsorcli/cli.git; then
    echo "Failed to clone the repository. Please check the branch name and network connection."
    exit 1
  fi

  if ! cd cli/cmd/windsor; then
    echo "Failed to navigate to the Windsor CLI directory."
    exit 1
  fi

  if ! go build -o "$WINDSORCLI_INSTALL_FOLDER"/windsor; then
    echo "Failed to build the Windsor CLI. Please ensure Go is installed and properly configured."
    exit 1
  fi
fi

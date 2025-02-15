#!/bin/bash

set -e

WINDSORCLI_EXE_PATH=$1
GITHUB_WORKSPACE=$2

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <WINDSORCLI_EXE_PATH> <GITHUB_WORKSPACE>"
  exit 1
fi

# Debug print for inputs
echo "WINDSORCLI_EXE_PATH: ${WINDSORCLI_EXE_PATH}"
echo "GITHUB_WORKSPACE: ${GITHUB_WORKSPACE}"

# Check if WINDSORCLI_EXE_PATH is set and executable
if [ -z "${WINDSORCLI_EXE_PATH}" ]; then
  echo "Error: WINDSORCLI_EXE_PATH is not set."
  exit 1
fi

if [ ! -x "${WINDSORCLI_EXE_PATH}" ]; then
  echo "Error: WINDSORCLI_EXE_PATH is not executable."
  exit 1
fi

# Check if GITHUB_WORKSPACE is set and is a directory
if [ -z "${GITHUB_WORKSPACE}" ]; then
  echo "Error: GITHUB_WORKSPACE is not set."
  exit 1
fi

if [ ! -d "${GITHUB_WORKSPACE}" ]; then
  echo "Error: GITHUB_WORKSPACE is not a directory."
  exit 1
fi

# Set WINDSOR_PROJECT_ROOT
export WINDSOR_PROJECT_ROOT=${GITHUB_WORKSPACE}

# Windsor Init
${WINDSORCLI_EXE_PATH} init local

# Disable DNS
echo "Disabling DNS in windsor.yaml"
yq -i '.contexts.local.dns.enabled = false' windsor.yaml > /dev/null 2>&1
cat windsor.yaml

# Windsor Up
${WINDSORCLI_EXE_PATH} context get
${WINDSORCLI_EXE_PATH} up --install --verbose
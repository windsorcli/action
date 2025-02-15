#!/bin/bash
set -e

WINDSORCLI_EXE_PATH=$1
CLEAN=$2

# Check the number of input parameters
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <WINDSORCLI_EXE_PATH> <CLEAN>"
  exit 1
fi

if [ -z "$WINDSORCLI_EXE_PATH" ]; then
    echo "Error: WINDSORCLI_EXE_PATH is not defined."
    exit 1
fi

if [ "$CLEAN" = true ]; then
    echo "Running Windsor Down with clean option..."
    "$WINDSORCLI_EXE_PATH" down --clean
else
    echo "Running Windsor Down without clean option..."
    "$WINDSORCLI_EXE_PATH" down
fi

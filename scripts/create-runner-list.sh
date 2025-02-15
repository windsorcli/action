#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <WINDSOR_TEST_CONFIG_FILE>"
  exit 1
fi

WINDSOR_TEST_CONFIG_FILE=$1

# Check if ${WINDSOR_TEST_CONFIG_FILE} exists and is not empty
if [ ! -s "${WINDSOR_TEST_CONFIG_FILE}" ]; then
  echo "Error: ${WINDSOR_TEST_CONFIG_FILE} is missing or empty."
  exit 1
fi

# Read runners list
runners_json=$(yq e -o=json '.runners' "${WINDSOR_TEST_CONFIG_FILE}" | jq -c .)
if [ "$runners_json" == "null" ]; then
  echo "Error: No runners found in ${WINDSOR_TEST_CONFIG_FILE}."
  exit 1
fi
# Prepare runner list
runner_list=$(echo "$runners_json" | jq -c 'map({os: .os, label: .label, arch: .arch})')
echo "runner_list=$runner_list" >> "$GITHUB_ENV"
echo "RUNNER_LIST=$runner_list" >> "$GITHUB_ENV"      

# RETURN: This is returned to the caller of this script
echo "$runner_list"

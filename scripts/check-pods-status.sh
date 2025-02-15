#!/bin/bash


WINDSORCLI_EXE_PATH="$1"

# Check the number of input parameters
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <WINDSORCLI_EXE_PATH>"
  exit 1
fi

# Fetch all pods in all namespaces in JSON format
"$WINDSORCLI_EXE_PATH" exec -- kubectl get pods -A -o json 2>/dev/null > pods.json
pods_json=$(cat pods.json)

# Check if the JSON output is empty
if [ -z "$pods_json" ]; then
  echo "No JSON output received. Please check if the Kubernetes cluster is accessible and has pods."
  exit 1
fi

# Check if the JSON output is valid
if ! echo "$pods_json" | jq empty; then
  echo "Invalid JSON output"
  exit 1
fi

# Use jq to parse the JSON and extract relevant information
# Format: NAMESPACE POD_NAME STATUS
pod_summary=$(echo "$pods_json" | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.status.phase)"')

# Initialize counters
running_count=0
non_running_count=0

# Print the header with fixed-width columns
printf "%-20s %-50s %-10s\n" "NAMESPACE" "POD_NAME" "STATUS"

# Process each line of the pod summary
while IFS= read -r line; do
  namespace=$(echo "$line" | awk '{print $1}')
  pod_name=$(echo "$line" | awk '{print $2}')
  status=$(echo "$line" | awk '{print $3}')
  
  # Print all pods with their status using fixed-width columns
  printf "%-20s %-50s %-10s\n" "$namespace" "$pod_name" "$status"
  
  if [ "$status" != "Running" ]; then
    ((non_running_count++))
  else
    ((running_count++))
  fi
done <<< "$pod_summary"

# Print summary
echo -e "\nSummary:"
echo "Running pods: $running_count"
echo "Non-running pods: $non_running_count"

# Exit with success if no non-running pods, otherwise exit with failure
if [ $non_running_count -eq 0 ]; then
  exit 0
else
  exit 1
fi

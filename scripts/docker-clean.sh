#!/bin/bash

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Docker is not installed. Exiting."
  exit 1
fi

# Check for running containers and remove them
containers=$(docker ps -aq)
if [ -n "$containers" ]; then
  echo "Removing containers..."
  docker rm -f "$containers"
else
  echo "No containers to remove."
fi

# Prune system, volumes, and networks
echo "Pruning Docker system, volumes, and networks..."
docker system prune -a -f
docker volume prune -f
docker network prune -f
docker system prune -a -f

# Remove .volumes directory if it exists
if [ -d ".volumes" ]; then
  echo "Removing .volumes directory..."
  rm -rf .volumes
else
  echo ".volumes directory does not exist."
fi

# Docker-Clean.ps1

# Check if Docker is installed
if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
  Write-Output "Docker is not installed. Exiting."
  exit 1
}

# Check for running containers and remove them
$containers = docker ps -aq
if ($containers) {
  Write-Output "Removing containers..."
  docker rm -f $containers
} else {
  Write-Output "No containers to remove."
}

# Prune system, volumes, and networks
Write-Output "Pruning Docker system, volumes, and networks..."
docker system prune -a -f
docker volume prune -f
docker network prune -f
docker system prune -a -f

#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_section() {
  echo -e "\n${BLUE}===== $1 =====${NC}"
}

print_info() {
  printf "%-25s: ${GREEN}%s${NC}\n" "$1" "$2"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

# Function to get current running image tags
get_running_versions() {
  local service_names=("nginx" "django" "te-log-server")
  declare -gA running_versions

  for service in "${service_names[@]}"; do
    container_id=$(docker ps -q --filter "name=${COMPOSE_PROJECT_NAME}-${service}-1")
    if [ -n "$container_id" ]; then
      running_versions["$service"]=$(docker inspect --format='{{.Config.Image}}' "$container_id" | cut -d: -f2)
    else
      running_versions["$service"]="Not running"
    fi
  done
}

# Function to compare versions
compare_versions() {
  local service=$1
  local running_version=$2
  local intended_version=$3

  if [ "$running_version" = "Not running" ]; then
    echo -e "${RED}Not running${NC}"
  elif [ "$running_version" = "$intended_version" ]; then
    echo -e "${GREEN}$running_version ✓${NC}"
  else
    echo -e "${YELLOW}$running_version → $intended_version ⚠️${NC}"
  fi
}

# Get running versions
get_running_versions

print_section "BUBLIK DEPLOYMENT STATUS"

print_section "Version Information"
print_info "Selected Version" "${IMAGE_TAG}"
echo -e "Service Versions:"
echo -e "  - Nginx: $(compare_versions "nginx" "${running_versions[nginx]}" "${IMAGE_TAG}")"
echo -e "  - Django: $(compare_versions "django" "${running_versions[django]}" "${IMAGE_TAG}")"
echo -e "  - Log Server: $(compare_versions "log-server" "${running_versions[log - server]}" "${IMAGE_TAG}")"

print_section "Docker Configuration"
print_info "Registry" "${DOCKER_REGISTRY}"
print_info "Organization" "${DOCKER_ORG}"

print_section "Admin Credentials"
print_info "Email" "${DJANGO_SUPERUSER_EMAIL}"
print_info "Password" "${DJANGO_SUPERUSER_PASSWORD}"

print_section "Instance Configuration"
print_info "FQDN" "${BUBLIK_FQDN}"
print_info "API URL" "${API_URL}"
print_info "Data Directory" "${BUBLIK_DOCKER_DATA_DIR}"
print_info "Proxy Port" "${BUBLIK_DOCKER_PROXY_PORT}"

print_section "Service Ports"
print_info "Django" "${BUBLIK_DOCKER_DJANGO_PORT}"
print_info "Log Server" "${BUBLIK_DOCKER_TE_LOG_SERVER_PORT}"
print_info "Documentation" "${BUBLIK_DOCKER_DOCS_PORT}"
print_info "AI Service" "${BUBLIK_AI_PORT}"
print_info "Database" "${DB_PORT}"
print_info "Redis" "${REDIS_PORT}"
print_info "RabbitMQ" "${RABBITMQ_PORT}"
print_info "Flower" "${FLOWER_PORT}"

print_section "Additional Information"
print_info "Project Name" "${COMPOSE_PROJECT_NAME}"
print_info "URL Prefix" "${URL_PREFIX:-None}"
print_info "Flower Prefix" "${FLOWER_URL_PREFIX}"
print_info "Docs URL" "${DOCS_URL}"

print_section "Container Status"
if command -v docker &>/dev/null && docker ps &>/dev/null; then
  if docker ps --filter "name=${COMPOSE_PROJECT_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "${COMPOSE_PROJECT_NAME}"; then
    print_success "Containers are running"
    docker ps --filter "name=${COMPOSE_PROJECT_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  else
    print_warning "No Bublik containers are running"
  fi
else
  print_error "Docker is not available or not running"
fi

# Add summary
echo -e "\n${PURPLE}=========================================${NC}"
echo -e "${CYAN}Deployment Summary:${NC}"
if [ "${running_versions[nginx]}" = "${IMAGE_TAG}" ] &&
  [ "${running_versions[django]}" = "${IMAGE_TAG}" ] &&
  [ "${running_versions[log - server]}" = "${IMAGE_TAG}" ]; then
  print_success "All services are running the selected version (${IMAGE_TAG})"
else
  print_warning "Version mismatch detected. Some services may need to be updated."
  echo -e "Run 'task docker:up' to update all services to version ${IMAGE_TAG}"
fi
echo -e "${PURPLE}=========================================${NC}"

#!/bin/bash
################################################################################
# Mystic Home Server - Offline Deployment Script
#
# Purpose: Single-command deployment for offline/air-gapped machines.
#          Runs preflight checks, loads images, sets up volumes, creates
#          the Docker network, and starts all services.
#
# Usage: sudo ./scripts/deploy.sh [OPTIONS]
#
# Author: Developer Agent - Mystic Home Server
################################################################################

set -e  # Exit on error

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DRY_RUN=false
SKIP_IMAGES=false
SKIP_VOLUMES=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Offline Deployment - Mystic Home Server${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    local step_num="$1"
    local total="$2"
    local description="$3"
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step ${step_num}/${total}: ${description}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

usage() {
    cat << EOF
Usage: sudo $0 [OPTIONS]

Single-command offline deployment for the Mystic Home Server. Runs preflight
checks, loads Docker images, sets up volumes, creates the Docker network,
and starts all services.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be done without making changes
    --skip-images       Skip loading Docker images from archives
    --skip-volumes      Skip importing volume data from archives

EXAMPLES:
    # Full deployment
    sudo ./scripts/deploy.sh

    # Dry run to preview all steps
    sudo ./scripts/deploy.sh --dry-run

    # Deploy without loading images (already loaded or will pull)
    sudo ./scripts/deploy.sh --skip-images

    # Deploy without importing volume data (start fresh)
    sudo ./scripts/deploy.sh --skip-volumes

PREREQUISITES:
    - Docker and Docker Compose v2 must be installed
    - For offline deployment, place image archives in docker-images/
    - For offline deployment, place volume archives in volume-exports/
    - Must be run as root (sudo)

EOF
    exit 0
}

################################################################################
# Step 0: Preflight Checks
################################################################################

preflight_checks() {
    print_info "Running preflight checks..."
    echo

    # Must be running as root
    if [[ $EUID -ne 0 ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            print_warning "Not running as root (allowed in dry-run mode)"
        else
            print_error "This script MUST be run as root"
            print_info "Please run: sudo $0"
            exit 1
        fi
    else
        print_success "Running as root"
    fi

    # docker-compose.yml must exist
    if [[ ! -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        print_error "docker-compose.yml not found at $PROJECT_DIR/docker-compose.yml"
        exit 1
    fi
    print_success "Found docker-compose.yml"

    # Docker installed and daemon running
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    print_success "Docker is installed"

    if ! docker info &> /dev/null 2>&1; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    print_success "Docker daemon is running"

    # Docker Compose v2 installed
    if ! docker compose version &> /dev/null 2>&1; then
        print_error "Docker Compose v2 is not installed (docker compose plugin)"
        exit 1
    fi
    local compose_version
    compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
    print_success "Docker Compose v2 is installed ($compose_version)"

    # Disk space check
    local available_gb
    available_gb=$(df --output=avail -BG "$PROJECT_DIR" 2>/dev/null | tail -1 | tr -d ' G')
    if [[ -n "$available_gb" ]] && [[ "$available_gb" =~ ^[0-9]+$ ]]; then
        if [[ "$available_gb" -lt 50 ]]; then
            print_warning "Low disk space: ${available_gb}GB available (recommended: 50GB+)"
        else
            print_success "Disk space: ${available_gb}GB available"
        fi
    else
        print_warning "Could not determine available disk space"
    fi

    # RAM check
    if [[ -f /proc/meminfo ]]; then
        local total_kb
        total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local total_gb=$(( total_kb / 1024 / 1024 ))
        if [[ "$total_gb" -lt 8 ]]; then
            print_warning "Low RAM: ${total_gb}GB total (recommended: 16GB+, minimum: 8GB)"
        elif [[ "$total_gb" -lt 16 ]]; then
            print_info "RAM: ${total_gb}GB total (16GB+ recommended for all services)"
        else
            print_success "RAM: ${total_gb}GB total"
        fi
    else
        print_warning "Could not determine total RAM"
    fi

    # GPU check (informational only)
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        local gpu_name
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        print_success "GPU detected: $gpu_name"
    else
        print_info "No NVIDIA GPU detected -- Ollama will not use GPU acceleration"
    fi

    echo
    print_success "Preflight checks passed"
}

################################################################################
# Step 1: Set up .env
################################################################################

setup_env() {
    if [[ "$DRY_RUN" == true ]]; then
        if [[ ! -f "$PROJECT_DIR/.env" ]]; then
            print_info "[DRY RUN] Would copy .env.example to .env"
        else
            print_info "[DRY RUN] .env already exists, would source it"
        fi
        print_info "[DRY RUN] Would remind to review MYSTIC_ROOT setting"
        return 0
    fi

    if [[ ! -f "$PROJECT_DIR/.env" ]]; then
        if [[ -f "$PROJECT_DIR/.env.example" ]]; then
            cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
            print_success "Created .env from .env.example"
        else
            print_warning ".env.example not found -- skipping .env creation"
            return 0
        fi
    else
        print_success ".env already exists"
    fi

    print_info "Reminder: review MYSTIC_ROOT in $PROJECT_DIR/.env"

    # Source the .env file
    set -a
    source "$PROJECT_DIR/.env"
    set +a
    print_success "Sourced .env (MYSTIC_ROOT=${MYSTIC_ROOT:-.})"
}

################################################################################
# Step 2: Load Docker images
################################################################################

load_images() {
    if [[ "$SKIP_IMAGES" == true ]]; then
        print_info "Skipping image loading (--skip-images)"
        return 0
    fi

    local images_dir="$PROJECT_DIR/docker-images"

    if [[ -d "$images_dir" ]]; then
        local tar_count
        tar_count=$(find "$images_dir" -maxdepth 1 -name "*.tar" -type f 2>/dev/null | wc -l)
        if [[ "$tar_count" -eq 0 ]]; then
            print_info "docker-images/ directory exists but contains no .tar files"
            return 0
        fi

        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would load $tar_count image archive(s) from $images_dir"
            return 0
        fi

        print_info "Loading $tar_count image archive(s) from $images_dir..."
        "$SCRIPT_DIR/load-images.sh" "$images_dir"
        print_success "Image loading complete"
    else
        print_info "No docker-images/ directory found -- images must be pulled or already loaded"
    fi
}

################################################################################
# Step 3: Set up volume directories
################################################################################

setup_volumes() {
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would run setup-volumes.sh --dry-run"
        "$SCRIPT_DIR/setup-volumes.sh" --dry-run
        return 0
    fi

    print_info "Creating volume directories with correct ownership..."
    "$SCRIPT_DIR/setup-volumes.sh"
    print_success "Volume directories ready"
}

################################################################################
# Step 4: Import volume data
################################################################################

import_volumes() {
    if [[ "$SKIP_VOLUMES" == true ]]; then
        print_info "Skipping volume import (--skip-volumes)"
        return 0
    fi

    local volumes_dir="$PROJECT_DIR/volume-exports"

    if [[ -d "$volumes_dir" ]]; then
        local archive_count
        archive_count=$(find "$volumes_dir" -maxdepth 1 -name "*-volume.tar.gz" -type f 2>/dev/null | wc -l)
        if [[ "$archive_count" -eq 0 ]]; then
            print_info "volume-exports/ directory exists but contains no archives"
            return 0
        fi

        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would import $archive_count volume archive(s) from $volumes_dir"
            return 0
        fi

        print_info "Importing $archive_count volume archive(s) from $volumes_dir..."
        "$SCRIPT_DIR/import-volumes.sh" --force "$volumes_dir"
        print_success "Volume import complete"
    else
        print_info "No volume-exports/ directory found -- volumes will start empty"
    fi
}

################################################################################
# Step 5: Create Docker network
################################################################################

create_network() {
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would create Docker network 'web'"
        return 0
    fi

    docker network create web 2>/dev/null || true
    print_success "Docker network 'web' is ready"
}

################################################################################
# Step 6: Start services
################################################################################

start_services() {
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would run: docker compose up -d"
        print_info "[DRY RUN] Would display service status"
        echo
        print_info "Service URLs that would be available:"
        echo "  home.mystic.home        Nginx gateway/landing page"
        echo "  cloud.mystic.home       Nextcloud"
        echo "  jenkins.mystic.home     Jenkins CI"
        echo "  bamboo.mystic.home      Bamboo"
        echo "  confluence.mystic.home  Confluence"
        echo "  jira.mystic.home        Jira"
        echo "  bitbucket.mystic.home   Bitbucket"
        echo "  chat.mystic.home        Mattermost"
        echo "  ai.mystic.home          Open WebUI (Ollama)"
        echo "  kibana.mystic.home      Kibana (ELK)"
        return 0
    fi

    print_info "Starting all services..."
    docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
    echo

    print_info "Service status:"
    docker compose -f "$PROJECT_DIR/docker-compose.yml" ps
    echo

    print_info "Service URLs:"
    echo "  home.mystic.home        Nginx gateway/landing page"
    echo "  cloud.mystic.home       Nextcloud"
    echo "  jenkins.mystic.home     Jenkins CI"
    echo "  bamboo.mystic.home      Bamboo"
    echo "  confluence.mystic.home  Confluence"
    echo "  jira.mystic.home        Jira"
    echo "  bitbucket.mystic.home   Bitbucket"
    echo "  chat.mystic.home        Mattermost"
    echo "  ai.mystic.home          Open WebUI (Ollama)"
    echo "  kibana.mystic.home      Kibana (ELK)"
    echo
    print_info "DNS: Add these hostnames to your local DNS server or /etc/hosts"
}

################################################################################
# Main Script
################################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-images)
                SKIP_IMAGES=true
                shift
                ;;
            --skip-volumes)
                SKIP_VOLUMES=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                ;;
            *)
                print_error "Unexpected argument: $1"
                usage
                ;;
        esac
    done

    # Print header
    print_header
    echo

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN MODE -- no changes will be made"
        echo
    fi

    # Show configuration
    print_info "Configuration:"
    echo "  Project Dir:    $PROJECT_DIR"
    echo "  Dry Run:        $DRY_RUN"
    echo "  Skip Images:    $SKIP_IMAGES"
    echo "  Skip Volumes:   $SKIP_VOLUMES"

    local total_steps=6

    # Step 0: Preflight checks
    print_step 0 "$total_steps" "Preflight checks"
    preflight_checks

    # Step 1: Set up .env
    print_step 1 "$total_steps" "Setting up environment"
    setup_env

    # Step 2: Load Docker images
    print_step 2 "$total_steps" "Loading Docker images"
    load_images

    # Step 3: Set up volume directories
    print_step 3 "$total_steps" "Setting up volume directories"
    setup_volumes

    # Step 4: Import volume data
    print_step 4 "$total_steps" "Importing volume data"
    import_volumes

    # Step 5: Create Docker network
    print_step 5 "$total_steps" "Creating Docker network"
    create_network

    # Step 6: Start services
    print_step 6 "$total_steps" "Starting services"
    start_services

    # Final summary
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}Dry Run Complete!${NC}"
    else
        echo -e "${GREEN}Deployment Complete!${NC}"
    fi
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "This was a DRY RUN -- no changes were made"
        print_info "Run without --dry-run to perform the deployment"
    else
        print_success "All services have been started"
        echo
        print_info "Next steps:"
        echo "  1. Configure DNS: add *.mystic.home entries to your DNS server or /etc/hosts"
        echo "  2. Verify services: docker compose -f $PROJECT_DIR/docker-compose.yml ps"
        echo "  3. View logs: docker compose -f $PROJECT_DIR/docker-compose.yml logs -f [service]"
        echo "  4. Traefik dashboard: http://<server-ip>:8080"
    fi
    echo
}

# Run main function
main "$@"

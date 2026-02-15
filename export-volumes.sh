#!/bin/bash
################################################################################
# Docker Volume Export Script
#
# Purpose: On an ONLINE machine, archive Docker volume directories as tarballs
#          for transfer to offline/air-gapped systems. Preserves file ownership
#          so container UIDs are maintained on the target machine.
#
# Usage: ./export-volumes.sh [OPTIONS] [OUTPUT_DIR]
#
# Author: Developer Agent - Mystic Home Server
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_OUTPUT="./volume-exports"
DEFAULT_ROOT="/data/docker"
DRY_RUN=false
FORCE=false
EXPORT_ALL=false
SERVICES=""
COMPOSE_FILE="docker-compose.yml"

# All known service volume directory names (top-level dirs under /data/docker)
ALL_SERVICES=(
    traefik
    gateway
    nextcloud
    mariadbone
    jenkins
    bamboo
    postgresdbfive
    confluence
    postgresdbone
    jira
    postgresdbtwo
    bitbucket
    postgresdbthree
    postgresdbfour
    mailserver
    mattermost
    ollama
    openwebui
    elasticsearch
    logstash
    kibana
)

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Docker Volume Export - Mystic Home Server${NC}"
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

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [OUTPUT_DIR]

Archive Docker volume directories as tarballs for transfer to offline/air-gapped
systems. Preserves file ownership (container UIDs) in the archives.

OPTIONS:
    -h, --help                      Show this help message
    -d, --dry-run                   Show what would be exported without changes
    -r, --root ROOT_PATH            Volume root directory (default: /data/docker)
    -f, --file FILE                 Specify docker-compose file (default: docker-compose.yml)
    --all                           Export all service volumes
    --services SERVICE1,SERVICE2    Export only specific service volumes (comma-separated)
    --force                         Skip confirmation prompts (auto-stop containers)

ARGUMENTS:
    OUTPUT_DIR      Directory to save .tar.gz archives (default: ./volume-exports/)

AVAILABLE SERVICES:
    traefik, gateway, nextcloud, mariadbone, jenkins, bamboo, postgresdbfive,
    confluence, postgresdbone, jira, postgresdbtwo, bitbucket, postgresdbthree,
    postgresdbfour, mailserver, mattermost, ollama, openwebui, elasticsearch,
    logstash, kibana

COMMON EXPORT SETS:
    # Pre-configured Jenkins with plugins
    ./export-volumes.sh --services jenkins

    # Ollama with pre-downloaded models
    ./export-volumes.sh --services ollama

    # Full Atlassian suite with databases
    ./export-volumes.sh --services confluence,postgresdbone,jira,postgresdbtwo,bitbucket,postgresdbthree

    # Everything
    ./export-volumes.sh --all

EXAMPLES:
    # Dry run to see what would be exported
    ./export-volumes.sh --all --dry-run

    # Export specific services
    ./export-volumes.sh --services jenkins,ollama,nextcloud

    # Export all volumes to USB drive
    sudo ./export-volumes.sh --all --force /mnt/usb/volume-exports

NOTES:
    - Must be run as root to preserve file ownership in archives
    - Containers for exported services will be stopped during archiving
    - Archives use gzip compression and preserve ownership (tar --numeric-owner)

EOF
    exit 0
}

check_requirements() {
    print_info "Checking requirements..."

    # Check if running as root
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == false ]]; then
        print_error "This script MUST be run as root to preserve file ownership"
        print_info "Please run: sudo $0 $*"
        exit 1
    fi
    if [[ $EUID -eq 0 ]]; then
        print_success "Running as root"
    fi

    # Check for Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    print_success "Docker is available"

    # Check for required commands
    for cmd in tar du; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Required command not found: $cmd"
            exit 1
        fi
    done
    print_success "All required commands found"

    echo
}

get_container_for_service() {
    # Map service directory name to container name
    # Most are the same, but some differ
    local service="$1"
    echo "$service"
}

stop_container() {
    local container="$1"

    # Check if the container is running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        print_info "  Stopping container: $container"
        if docker stop "$container" > /dev/null 2>&1; then
            print_success "  Stopped $container"
            return 0
        else
            print_warning "  Could not stop $container (may not exist)"
            return 1
        fi
    else
        print_info "  Container $container is not running"
        return 0
    fi
}

start_container() {
    local container="$1"

    print_info "  Restarting container: $container"
    if docker start "$container" > /dev/null 2>&1; then
        print_success "  Restarted $container"
    else
        print_warning "  Could not restart $container"
    fi
}

export_service() {
    local service="$1"
    local root_path="$2"
    local output_dir="$3"
    local service_path="$root_path/$service"

    if [[ ! -d "$service_path" ]]; then
        print_warning "Volume directory not found: $service_path (skipping)"
        return 0
    fi

    local archive_name="${service}-volume.tar.gz"
    local archive_path="$output_dir/$archive_name"
    local container
    container=$(get_container_for_service "$service")

    if [[ "$DRY_RUN" == true ]]; then
        local dir_size
        dir_size=$(du -sh "$service_path" 2>/dev/null | cut -f1)
        print_info "[DRY RUN] Would export: $service_path ($dir_size)"
        print_info "           Archive: $archive_name"
        print_info "           Container to stop: $container"
        return 0
    fi

    # Stop the container before archiving
    local was_running=false
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        was_running=true
    fi

    if [[ "$was_running" == true ]]; then
        if [[ "$FORCE" == false ]]; then
            echo -en "  Container ${YELLOW}$container${NC} is running. Stop it for export? [y/N] "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_warning "  Skipping $service (container still running)"
                return 0
            fi
        fi
        stop_container "$container"
    fi

    # Create the archive
    print_info "  Archiving $service_path..."
    if tar czf "$archive_path" --numeric-owner -C "$root_path" "$service"; then
        local archive_size
        archive_size=$(du -h "$archive_path" | cut -f1)
        print_success "  Created $archive_name ($archive_size)"
    else
        print_error "  Failed to archive $service"
        # Clean up partial archive
        rm -f "$archive_path"
        # Restart the container if it was running
        if [[ "$was_running" == true ]]; then
            start_container "$container"
        fi
        return 1
    fi

    # Restart the container if it was running before
    if [[ "$was_running" == true ]]; then
        start_container "$container"
    fi

    return 0
}

print_summary() {
    local output_dir="$1"
    local exported_count="$2"
    local total_count="$3"

    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Export Complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Output Dir:       ${BLUE}$output_dir${NC}"
    echo -e "Volumes Exported: ${BLUE}$exported_count / $total_count${NC}"

    if [[ "$DRY_RUN" == false ]] && [[ -d "$output_dir" ]]; then
        local total_size
        total_size=$(du -sh "$output_dir" 2>/dev/null | cut -f1)
        echo -e "Total Size:       ${BLUE}$total_size${NC}"
        echo
        print_info "Archives created:"
        for f in "$output_dir"/*-volume.tar.gz; do
            if [[ -f "$f" ]]; then
                local fsize
                fsize=$(du -h "$f" | cut -f1)
                echo "  $(basename "$f")  ($fsize)"
            fi
        done
    fi

    echo
    print_info "Next steps:"
    echo "  1. Copy the $output_dir directory to portable media"
    echo "  2. Transfer to the offline/air-gapped machine"
    echo "  3. Run ./import-volumes.sh to restore the volumes"
    echo
}

################################################################################
# Main Script
################################################################################

main() {
    local output_dir="$DEFAULT_OUTPUT"
    local root_path="$DEFAULT_ROOT"

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
            -r|--root)
                root_path="$2"
                shift 2
                ;;
            -f|--file)
                COMPOSE_FILE="$2"
                shift 2
                ;;
            --all)
                EXPORT_ALL=true
                shift
                ;;
            --services)
                SERVICES="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                ;;
            *)
                output_dir="$1"
                shift
                ;;
        esac
    done

    # Validate that either --all or --services is specified
    if [[ "$EXPORT_ALL" == false ]] && [[ -z "$SERVICES" ]]; then
        print_error "You must specify either --all or --services SERVICE1,SERVICE2,..."
        echo
        usage
    fi

    # Print header
    print_header
    echo

    # Build the list of services to export
    local services_to_export=()

    if [[ "$EXPORT_ALL" == true ]]; then
        services_to_export=("${ALL_SERVICES[@]}")
    else
        IFS=',' read -ra services_to_export <<< "$SERVICES"
    fi

    # Validate service names
    for svc in "${services_to_export[@]}"; do
        local valid=false
        for known in "${ALL_SERVICES[@]}"; do
            if [[ "$svc" == "$known" ]]; then
                valid=true
                break
            fi
        done
        if [[ "$valid" == false ]]; then
            print_error "Unknown service: $svc"
            print_info "Valid services: ${ALL_SERVICES[*]}"
            exit 1
        fi
    done

    # Show configuration
    print_info "Configuration:"
    echo "  Volume Root:   $root_path"
    echo "  Output Dir:    $output_dir"
    echo "  Services:      ${services_to_export[*]}"
    echo "  Force:         $FORCE"
    echo "  Dry Run:       $DRY_RUN"
    echo

    # Check requirements
    check_requirements

    # Validate volume root exists
    if [[ ! -d "$root_path" ]]; then
        print_error "Volume root directory not found: $root_path"
        exit 1
    fi
    print_success "Volume root exists: $root_path"
    echo

    # Create output directory
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$output_dir"
        print_success "Output directory ready: $output_dir"
    fi
    echo

    # Export each service
    local total=${#services_to_export[@]}
    local current=0
    local exported=0

    for service in "${services_to_export[@]}"; do
        ((current++)) || true
        echo -e "${BLUE}[$current/$total]${NC} Exporting: $service"

        if export_service "$service" "$root_path" "$output_dir"; then
            ((exported++)) || true
        fi

        echo
    done

    # Print summary
    print_summary "$output_dir" "$exported" "$total"

    if [[ "$DRY_RUN" == true ]]; then
        echo
        print_warning "This was a DRY RUN - no changes were made"
        print_info "Run without --dry-run to create archives"
        echo
    fi
}

# Run main function
main "$@"

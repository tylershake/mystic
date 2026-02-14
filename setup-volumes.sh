#!/bin/bash
################################################################################
# Docker Volume Setup Script
#
# Purpose: Create all volume directories defined in docker-compose.yml with
#          proper permissions for home server infrastructure
#
# Usage: ./setup-volumes.sh [OPTIONS] [ROOT_PATH]
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
DEFAULT_ROOT="/data/docker"
DRY_RUN=false
VERBOSE=false
COMPOSE_FILE="docker-compose.yml"

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Docker Volume Setup - Mystic Home Server${NC}"
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
Usage: $0 [OPTIONS] [ROOT_PATH]

Create all Docker volume directories from docker-compose.yml with proper permissions.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be created without making changes
    -v, --verbose       Enable verbose output
    -f, --file FILE     Specify docker-compose file (default: docker-compose.yml)
    -o, --owner USER    Set directory owner (default: current user)
    -g, --group GROUP   Set directory group (default: current user's group)

ARGUMENTS:
    ROOT_PATH           Root directory for volumes (default: /data/docker)

EXAMPLES:
    # Use default /data/docker
    sudo ./setup-volumes.sh

    # Use custom root path
    sudo ./setup-volumes.sh /mnt/storage/docker

    # Dry run to see what would be created
    ./setup-volumes.sh --dry-run

    # Set specific owner
    sudo ./setup-volumes.sh --owner 1000 --group 1000

EOF
    exit 0
}

check_requirements() {
    print_info "Checking requirements..."

    # Check if docker-compose.yml exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_error "Docker compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    print_success "Found $COMPOSE_FILE"

    # Check if running as root (needed for directory creation)
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == false ]]; then
        print_warning "Not running as root. You may need sudo for directory creation."
        print_info "Consider using: sudo $0 $@"
    fi

    # Check for required commands
    for cmd in grep sed mkdir chmod chown; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Required command not found: $cmd"
            exit 1
        fi
    done
    print_success "All required commands found"

    echo
}

extract_volumes() {
    local root_path="$1"
    print_info "Extracting volume paths from $COMPOSE_FILE..."

    # Extract volume mount paths that start with /data/docker or absolute paths
    # Format: - /host/path:/container/path or - /host/path:/container/path:options
    local volumes=$(grep -E '^\s+- /.+:.+' "$COMPOSE_FILE" | \
                    sed -E 's/^\s+- ([^:]+):.*$/\1/' | \
                    grep -v '/var/run/docker.sock' | \
                    grep -v '/dev/shm' | \
                    sort -u)

    if [[ -z "$volumes" ]]; then
        print_error "No volumes found in $COMPOSE_FILE"
        exit 1
    fi

    # Replace /data/docker with custom root path if provided
    if [[ "$root_path" != "/data/docker" ]]; then
        volumes=$(echo "$volumes" | sed "s|/data/docker|$root_path|g")
    fi

    echo "$volumes"
}

create_directory() {
    local dir="$1"
    local owner="${2:-$SUDO_USER}"
    local group="${3:-$SUDO_USER}"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would create: $dir (owner: $owner:$group)"
        return 0
    fi

    # Create directory if it doesn't exist
    if [[ -d "$dir" ]]; then
        print_warning "Directory already exists: $dir"
    else
        if mkdir -p "$dir"; then
            print_success "Created: $dir"
        else
            print_error "Failed to create: $dir"
            return 1
        fi
    fi

    # Set permissions (755 = rwxr-xr-x)
    if chmod 755 "$dir"; then
        [[ "$VERBOSE" == true ]] && print_info "  Set permissions: 755"
    else
        print_warning "  Failed to set permissions for: $dir"
    fi

    # Set ownership
    if [[ -n "$owner" ]] && [[ -n "$group" ]]; then
        if chown "$owner:$group" "$dir" 2>/dev/null; then
            [[ "$VERBOSE" == true ]] && print_info "  Set ownership: $owner:$group"
        else
            [[ "$VERBOSE" == true ]] && print_warning "  Could not set ownership (may require root)"
        fi
    fi
}

setup_special_permissions() {
    local root_path="$1"

    print_info "Setting up special permissions for specific services..."

    # PostgreSQL directories - need to be writable by postgres user (UID 999 or 70)
    local postgres_dirs=(
        "$root_path/postgresdbone"
        "$root_path/postgresdbtwo"
        "$root_path/postgresdbthree"
        "$root_path/postgresdbfour"
    )

    for dir in "${postgres_dirs[@]}"; do
        if [[ -d "$dir" ]] && [[ "$DRY_RUN" == false ]]; then
            chmod 750 "$dir" 2>/dev/null || true
            [[ "$VERBOSE" == true ]] && print_info "  Set PostgreSQL permissions for: $dir"
        fi
    done

    # MariaDB directory
    if [[ -d "$root_path/mariadbone" ]] && [[ "$DRY_RUN" == false ]]; then
        chmod 750 "$root_path/mariadbone" 2>/dev/null || true
        [[ "$VERBOSE" == true ]] && print_info "  Set MariaDB permissions for: $root_path/mariadbone"
    fi

    print_success "Special permissions configured"
}

print_summary() {
    local root_path="$1"
    local dir_count="$2"

    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Setup Complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Root Path:    ${BLUE}$root_path${NC}"
    echo -e "Directories:  ${BLUE}$dir_count${NC}"
    echo
    print_info "Next steps:"
    echo "  1. Review the created directories: ls -la $root_path"
    echo "  2. Create the external network: docker network create web"
    echo "  3. Start your services: docker compose up -d"
    echo
}

################################################################################
# Main Script
################################################################################

main() {
    local root_path="$DEFAULT_ROOT"
    local owner="${SUDO_USER:-$USER}"
    local group="${SUDO_USER:-$USER}"

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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--file)
                COMPOSE_FILE="$2"
                shift 2
                ;;
            -o|--owner)
                owner="$2"
                shift 2
                ;;
            -g|--group)
                group="$2"
                shift 2
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                ;;
            *)
                root_path="$1"
                shift
                ;;
        esac
    done

    # Print header
    print_header
    echo

    # Show configuration
    print_info "Configuration:"
    echo "  Root Path:     $root_path"
    echo "  Compose File:  $COMPOSE_FILE"
    echo "  Owner:         $owner:$group"
    echo "  Dry Run:       $DRY_RUN"
    echo

    # Check requirements
    check_requirements

    # Extract volumes from docker-compose.yml
    volumes=$(extract_volumes "$root_path")
    volume_count=$(echo "$volumes" | wc -l)

    print_success "Found $volume_count volume paths"
    echo

    if [[ "$VERBOSE" == true ]]; then
        print_info "Volume paths:"
        echo "$volumes" | while read -r vol; do
            echo "  - $vol"
        done
        echo
    fi

    # Create directories
    print_info "Creating directories..."
    echo

    dir_count=0
    while IFS= read -r volume_path; do
        [[ -z "$volume_path" ]] && continue
        create_directory "$volume_path" "$owner" "$group"
        ((dir_count++))
    done <<< "$volumes"

    echo

    # Setup special permissions for database directories
    if [[ "$DRY_RUN" == false ]]; then
        setup_special_permissions "$root_path"
    fi

    # Print summary
    print_summary "$root_path" "$dir_count"

    if [[ "$DRY_RUN" == true ]]; then
        echo
        print_warning "This was a DRY RUN - no changes were made"
        print_info "Run without --dry-run to create directories"
        echo
    fi
}

# Run main function
main "$@"

#!/bin/bash
################################################################################
# Docker Volume Setup Script
#
# Purpose: Create all volume directories defined in docker-compose.yml with
#          correct permissions for each container's user
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
# Container UID/GID Mappings
# These must match the UIDs that containers run as
################################################################################

declare -A SERVICE_UIDS=(
    ["postgres"]=999          # PostgreSQL runs as postgres:postgres (999:999)
    ["mariadb"]=999          # MariaDB runs as mysql:mysql (999:999)
    ["nextcloud"]=33         # Nextcloud runs as www-data (33:33) on Debian
    ["jenkins"]=1000         # Jenkins runs as jenkins:jenkins (1000:1000)
    ["bamboo"]=2005          # Bamboo runs as bamboo (2005:2005)
    ["confluence"]=2002      # Confluence runs as confluence (2002:2002)
    ["jira"]=2001            # Jira runs as jira (2001:2001)
    ["bitbucket"]=2003       # Bitbucket runs as bitbucket (2003:2003)
    ["mattermost"]=2000      # Mattermost runs as UID 2000
    ["mailserver"]=5000      # Docker-mailserver runs as UID 5000
    ["gateway"]=101          # Nginx (alpine) runs as nginx user (101:101)
    ["traefik"]=0            # Traefik runs as root (needs docker socket access)
)

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

Create all Docker volume directories from docker-compose.yml with correct
permissions for each container's UID.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be created without making changes
    -v, --verbose       Enable verbose output
    -f, --file FILE     Specify docker-compose file (default: docker-compose.yml)

ARGUMENTS:
    ROOT_PATH           Root directory for volumes (default: /data/docker)

CONTAINER UIDs USED:
    PostgreSQL:     999:999
    MariaDB:        999:999
    Nextcloud:      33:33 (www-data)
    Jenkins:        1000:1000
    Bamboo:         2005:2005
    Confluence:     2002:2002
    Jira:           2001:2001
    Bitbucket:      2003:2003
    Mattermost:     2000:2000
    Mail Server:    5000:5000
    Gateway:        101:101 (nginx)
    Traefik:        0:0 (root)

EXAMPLES:
    # Dry run to see what will be created
    ./setup-volumes.sh --dry-run

    # Create with default /data/docker
    sudo ./setup-volumes.sh

    # Use custom root path
    sudo ./setup-volumes.sh /mnt/storage/docker

IMPORTANT:
    This script MUST be run as root to set container UIDs properly!

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

    # Check if running as root
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == false ]]; then
        print_error "This script MUST be run as root to set proper UIDs"
        print_info "Please run: sudo $0 $@"
        exit 1
    fi

    # Check for required commands
    for cmd in grep sed mkdir chmod chown; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Required command not found: $cmd"
            exit 1
        fi
    done
    print_success "All required commands found"
    print_success "Running as root - can set container UIDs"

    echo
}

get_service_uid() {
    local dir_path="$1"
    local dir_name=$(basename "$dir_path")

    # Determine which service this directory belongs to
    case "$dir_path" in
        *postgres*)
            echo "${SERVICE_UIDS[postgres]}"
            ;;
        *mariadb*)
            echo "${SERVICE_UIDS[mariadb]}"
            ;;
        *nextcloud*)
            echo "${SERVICE_UIDS[nextcloud]}"
            ;;
        *jenkins*)
            echo "${SERVICE_UIDS[jenkins]}"
            ;;
        *bamboo*)
            echo "${SERVICE_UIDS[bamboo]}"
            ;;
        *confluence*)
            echo "${SERVICE_UIDS[confluence]}"
            ;;
        *jira*)
            echo "${SERVICE_UIDS[jira]}"
            ;;
        *bitbucket*)
            echo "${SERVICE_UIDS[bitbucket]}"
            ;;
        *mattermost*)
            echo "${SERVICE_UIDS[mattermost]}"
            ;;
        *mailserver*|*mail*)
            echo "${SERVICE_UIDS[mailserver]}"
            ;;
        *gateway*)
            echo "${SERVICE_UIDS[gateway]}"
            ;;
        *traefik*)
            echo "${SERVICE_UIDS[traefik]}"
            ;;
        *)
            # Default to root for unknown services
            echo "0"
            ;;
    esac
}

extract_volumes() {
    local root_path="$1"
    print_info "Extracting volume paths from $COMPOSE_FILE..." >&2

    # Extract volume mount paths
    local volumes=$(grep -E '^\s+- /.+:.+' "$COMPOSE_FILE" | \
                    sed -E 's/^\s+- ([^:]+):.*$/\1/' | \
                    grep -v '/var/run/docker.sock' | \
                    grep -v '/dev/shm' | \
                    sort -u)

    if [[ -z "$volumes" ]]; then
        print_error "No volumes found in $COMPOSE_FILE" >&2
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
    local uid="$2"
    local gid="$2"  # Using same value for GID as UID

    local perms="755"

    # Database directories get more restrictive permissions
    if [[ "$dir" == *"postgres"* ]] || [[ "$dir" == *"mariadb"* ]]; then
        perms="750"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would create: $dir"
        print_info "           Ownership: $uid:$gid"
        print_info "           Permissions: $perms"
        return 0
    fi

    # Create directory if it doesn't exist
    if [[ -d "$dir" ]]; then
        print_warning "Already exists: $dir"
    else
        if mkdir -p "$dir"; then
            print_success "Created: $dir"
        else
            print_error "Failed to create: $dir"
            return 1
        fi
    fi

    # Set ownership FIRST (before restrictive permissions)
    if chown "$uid:$gid" "$dir"; then
        if [[ "$VERBOSE" == true ]]; then print_info "  Ownership: $uid:$gid"; fi
    else
        print_error "  Failed to set ownership: $uid:$gid"
        return 1
    fi

    # Set permissions AFTER ownership
    if chmod "$perms" "$dir"; then
        if [[ "$VERBOSE" == true ]]; then print_info "  Permissions: $perms"; fi
    else
        print_warning "  Failed to set permissions: $perms"
    fi

    return 0
}

verify_uids() {
    print_info "Verifying container UIDs exist on system..."

    local missing_uids=()

    for uid in $(echo "${SERVICE_UIDS[@]}" | tr ' ' '\n' | sort -u); do
        if [[ "$uid" == "0" ]]; then
            continue  # Skip root
        fi

        # Check if UID exists
        if ! getent passwd "$uid" > /dev/null 2>&1; then
            missing_uids+=("$uid")
        fi
    done

    if [[ ${#missing_uids[@]} -gt 0 ]]; then
        print_warning "Some container UIDs don't exist on host system: ${missing_uids[*]}"
        print_info "This is NORMAL - Docker containers use their own user namespaces"
        print_info "The directories will still be owned by these UIDs"
    else
        print_success "UID verification complete"
    fi

    echo
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
    print_success "All directories created with correct container UIDs"
    echo
    print_info "Verify ownership:"
    echo "  ls -lan $root_path"
    echo
    print_info "Next steps:"
    echo "  1. Create the external network: docker network create web"
    echo "  2. Start your services: docker compose up -d"
    echo "  3. Check container logs: docker compose logs -f"
    echo
}

################################################################################
# Main Script
################################################################################

main() {
    local root_path="$DEFAULT_ROOT"
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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
    echo "  Dry Run:       $DRY_RUN"
    echo

    # Check requirements
    check_requirements

    # Verify UIDs
    verify_uids

    # Extract volumes from docker-compose.yml
    volumes=$(extract_volumes "$root_path")
    volume_count=$(echo "$volumes" | wc -l)

    print_success "Found $volume_count volume paths"
    echo

    if [[ "$VERBOSE" == true ]]; then
        print_info "Volume paths:"
        echo "$volumes" | while read -r vol; do
            local uid=$(get_service_uid "$vol")
            echo "  - $vol (UID: $uid)"
        done
        echo
    fi

    # Create directories
    print_info "Creating directories with correct UIDs..."
    echo

    dir_count=0
    while IFS= read -r volume_path; do
        [[ -z "$volume_path" ]] && continue

        # If the path looks like a file (has an extension), create only its
        # parent directory. This prevents mkdir from creating files like
        # traefik.toml or nginx.conf as directories.
        if [[ "$volume_path" =~ \.[a-zA-Z0-9]+$ ]]; then
            volume_path=$(dirname "$volume_path")
        fi

        # Get the appropriate UID for this service
        uid=$(get_service_uid "$volume_path")

        create_directory "$volume_path" "$uid"
        ((dir_count++)) || true
    done <<< "$volumes"

    echo

    # Copy configuration files
    print_info "Copying configuration files..."
    if [[ -f "$SCRIPT_DIR/config/traefik.toml" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] Would copy: config/traefik.toml → $root_path/traefik/traefik.toml"
        else
            cp "$SCRIPT_DIR/config/traefik.toml" "$root_path/traefik/traefik.toml"
            # Set ownership to match traefik container (root)
            chown 0:0 "$root_path/traefik/traefik.toml"
            chmod 644 "$root_path/traefik/traefik.toml"
            print_success "Copied: config/traefik.toml → $root_path/traefik/traefik.toml"
        fi
    else
        print_warning "config/traefik.toml not found in repo — skipping"
    fi
    echo

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

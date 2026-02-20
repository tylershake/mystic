#!/bin/bash
################################################################################
# Docker Volume Import Script
#
# Purpose: On an OFFLINE machine, extract volume archive tarballs into the
#          Docker volume root directory, preserving file ownership (container
#          UIDs).
#
# Usage: ./import-volumes.sh [OPTIONS] [INPUT_DIR]
#
# Author: Developer Agent - Mystic Home Server
################################################################################

set -e  # Exit on error

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a; source "$PROJECT_DIR/.env"; set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_INPUT="./volume-exports"
DEFAULT_ROOT="${MYSTIC_ROOT:-.}"
DRY_RUN=false
FORCE=false
FILTER=""

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Docker Volume Import - Mystic Home Server${NC}"
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
Usage: $0 [OPTIONS] [INPUT_DIR]

Extract volume archive tarballs into the Docker volume root directory on an
offline/air-gapped machine. Preserves file ownership so container UIDs are
maintained correctly.

OPTIONS:
    -h, --help                  Show this help message
    -d, --dry-run               Show what would be imported without making changes
    -r, --root ROOT_PATH        Volume root directory (default: MYSTIC_ROOT from .env, or current directory)
    --filter PATTERN            Only import archives matching PATTERN (grep -i, e.g. "jenkins")

ARGUMENTS:
    INPUT_DIR       Directory containing *-volume.tar.gz files (default: ./volume-exports/)

EXAMPLES:
    # Dry run to see what would be imported
    ./import-volumes.sh --dry-run

    # Import all volume archives to default MYSTIC_ROOT
    sudo ./import-volumes.sh

    # Import from USB drive to custom root
    sudo ./import-volumes.sh -r /mnt/storage/docker /mnt/usb/volume-exports

    # Import only a specific volume
    sudo ./import-volumes.sh --filter jenkins

NOTES:
    - MUST be run as root to preserve file ownership (container UIDs)
    - Archives should have been created by export-volumes.sh
    - If target directories already exist, you will be prompted to skip or overwrite
    - Does NOT require internet access

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

    # Check for required commands
    for cmd in tar du mkdir; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Required command not found: $cmd"
            exit 1
        fi
    done
    print_success "All required commands found"

    echo
}

extract_service_name() {
    # Extract service name from archive filename: servicename-volume.tar.gz -> servicename
    local filename
    filename=$(basename "$1")
    echo "${filename%-volume.tar.gz}"
}

import_archive() {
    local archive="$1"
    local root_path="$2"
    local service_name
    service_name=$(extract_service_name "$archive")
    local target_dir="$root_path/$service_name"

    if [[ "$DRY_RUN" == true ]]; then
        local archive_size
        archive_size=$(du -h "$archive" | cut -f1)
        print_info "[DRY RUN] Would import: $(basename "$archive") ($archive_size)"
        print_info "           Target: $target_dir"
        if [[ -d "$target_dir" ]]; then
            print_warning "           Target directory already exists!"
        fi
        return 0
    fi

    # Check if target directory already exists
    if [[ -d "$target_dir" ]]; then
        local response
        if [[ "$FORCE" == true ]]; then
            response="o"
        else
            print_warning "  Target directory already exists: $target_dir"
            echo -en "  [S]kip, [O]verwrite, or [B]ackup and replace? [s/o/b] "
            read -r response
        fi
        case "$response" in
            [Oo])
                print_info "  Removing existing directory..."
                rm -rf "$target_dir"
                ;;
            [Bb])
                local backup_name="${target_dir}.backup.$(date +%Y%m%d%H%M%S)"
                print_info "  Backing up to: $backup_name"
                mv "$target_dir" "$backup_name"
                print_success "  Backup created"
                ;;
            *)
                print_info "  Skipping $service_name"
                return 0
                ;;
        esac
    fi

    # Ensure root path exists
    mkdir -p "$root_path"

    # Extract the archive
    print_info "  Extracting to $root_path..."
    if tar xzf "$archive" --numeric-owner -C "$root_path"; then
        local dir_size
        if [[ -d "$target_dir" ]]; then
            dir_size=$(du -sh "$target_dir" 2>/dev/null | cut -f1)
        else
            dir_size="unknown"
        fi
        print_success "  Extracted $service_name ($dir_size)"
    else
        print_error "  Failed to extract $(basename "$archive")"
        print_warning "  Partial extraction may remain at $target_dir — verify manually"
        return 1
    fi

    return 0
}

print_summary() {
    local root_path="$1"
    local imported_count="$2"
    local total_count="$3"

    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Import Complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Volume Root:      ${BLUE}$root_path${NC}"
    echo -e "Volumes Imported: ${BLUE}$imported_count / $total_count${NC}"

    if [[ "$DRY_RUN" == false ]] && [[ -d "$root_path" ]]; then
        echo
        print_info "Imported directories:"
        ls -ld "$root_path"/*/ 2>/dev/null | while IFS= read -r line; do
            echo "  $line"
        done
    fi

    echo
    print_info "Verify ownership:"
    echo "  ls -lan $root_path"
    echo
    print_info "Next steps:"
    echo "  1. Verify volume permissions: ls -lan $root_path"
    echo "  2. Load Docker images: ./load-images.sh"
    echo "  3. Create the external network: docker network create web"
    echo "  4. Start services: docker compose up -d"
    echo
}

################################################################################
# Main Script
################################################################################

main() {
    local input_dir="$DEFAULT_INPUT"
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
            --filter)
                FILTER="$2"
                shift 2
                ;;
            -y|--force)
                FORCE=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                ;;
            *)
                input_dir="$1"
                shift
                ;;
        esac
    done

    # Print header
    print_header
    echo

    # Show configuration
    print_info "Configuration:"
    echo "  Input Dir:     $input_dir"
    echo "  Volume Root:   $root_path"
    echo "  Filter:        ${FILTER:-<none>}"
    echo "  Dry Run:       $DRY_RUN"
    echo

    # Check requirements
    check_requirements

    # Validate input directory
    if [[ ! -d "$input_dir" ]]; then
        print_error "Input directory not found: $input_dir"
        print_info "Run export-volumes.sh on a configured machine first to create archives"
        exit 1
    fi

    # Find all volume archive files
    if [[ -n "$FILTER" ]]; then
        mapfile -t archives < <(find "$input_dir" -maxdepth 1 -name "*-volume.tar.gz" -type f | grep -i "$FILTER" | sort)
    else
        mapfile -t archives < <(find "$input_dir" -maxdepth 1 -name "*-volume.tar.gz" -type f | sort)
    fi
    local total=${#archives[@]}

    if [[ $total -eq 0 ]]; then
        if [[ -n "$FILTER" ]]; then
            print_error "No volume archives matching '$FILTER' in $input_dir"
        else
            print_error "No *-volume.tar.gz files found in $input_dir"
            print_info "Run export-volumes.sh on a configured machine first to create archives"
        fi
        exit 1
    fi

    print_success "Found $total volume archive(s) in $input_dir"
    echo

    # Show archive list
    print_info "Archives to import:"
    for archive in "${archives[@]}"; do
        local archive_size service_name
        archive_size=$(du -h "$archive" | cut -f1)
        service_name=$(extract_service_name "$archive")
        echo "  - $(basename "$archive")  ($archive_size)  ->  $root_path/$service_name"
    done
    echo

    if [[ "$DRY_RUN" == true ]]; then
        # Still show what would happen per archive
        for archive in "${archives[@]}"; do
            import_archive "$archive" "$root_path"
        done
        echo
        print_warning "This was a DRY RUN - no changes were made"
        print_summary "$root_path" "0 (dry run)" "$total"
        return 0
    fi

    # Confirm before proceeding
    if [[ "$FORCE" == false ]]; then
        echo -en "Proceed with importing $total volume(s) to ${BLUE}$root_path${NC}? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Aborted by user"
            exit 0
        fi
    fi
    echo

    # Ensure root path exists
    mkdir -p "$root_path"
    print_success "Volume root directory ready: $root_path"
    echo

    # Import each archive
    local current=0
    local imported=0

    for archive in "${archives[@]}"; do
        ((current++)) || true
        local archive_size
        archive_size=$(du -h "$archive" | cut -f1)

        echo -e "${BLUE}[$current/$total]${NC} Importing: $(basename "$archive") ($archive_size)"

        if import_archive "$archive" "$root_path"; then
            ((imported++)) || true
        fi

        echo
    done

    # Print summary
    print_summary "$root_path" "$imported" "$total"
}

# Run main function
main "$@"

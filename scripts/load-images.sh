#!/bin/bash
################################################################################
# Docker Image Load Script
#
# Purpose: On an OFFLINE machine, load all Docker image .tar files from a
#          directory into the local Docker daemon.
#
# Usage: ./load-images.sh [OPTIONS] [INPUT_DIR]
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
DEFAULT_INPUT="./docker-images"
DRY_RUN=false
FILTER=""

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Docker Image Load - Mystic Home Server${NC}"
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

Load all Docker image .tar files from a directory into the local Docker daemon.
Intended for use on offline/air-gapped systems after transferring images with
save-images.sh.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be loaded without making changes
    --filter PATTERN    Only load .tar files matching PATTERN (grep -i, e.g. "jenkins")

ARGUMENTS:
    INPUT_DIR           Directory containing .tar files (default: ./docker-images/)

EXAMPLES:
    # Dry run to see what images would be loaded
    ./load-images.sh --dry-run

    # Load all images from default directory
    ./load-images.sh

    # Load from a custom directory
    ./load-images.sh /mnt/usb/docker-images

    # Load only a specific image
    ./load-images.sh --filter jenkins

NOTES:
    - Requires Docker to be installed and running
    - Does NOT require internet access
    - .tar files should have been created by save-images.sh or docker save

EOF
    exit 0
}

check_requirements() {
    print_info "Checking requirements..."

    # Check for Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    print_success "Docker is available"

    # Check Docker is running
    if ! docker info &> /dev/null 2>&1; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    print_success "Docker daemon is running"

    echo
}

print_summary() {
    local input_dir="$1"
    local loaded_count="$2"
    local total_count="$3"

    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Load Complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Input Dir:      ${BLUE}$input_dir${NC}"
    echo -e "Images Loaded:  ${BLUE}$loaded_count / $total_count${NC}"
    echo

    if [[ "$DRY_RUN" == false ]]; then
        print_info "Loaded images:"
        docker images --format "  {{.Repository}}:{{.Tag}}  ({{.Size}})" | head -20
        echo
    fi

    print_info "Next steps:"
    echo "  1. Run ./setup-volumes.sh to create volume directories"
    echo "  2. Create the external network: docker network create web"
    echo "  3. Start services: docker compose up -d"
    echo
}

################################################################################
# Main Script
################################################################################

main() {
    local input_dir="$DEFAULT_INPUT"

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
            --filter)
                FILTER="$2"
                shift 2
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
    echo "  Input Dir:   $input_dir"
    echo "  Filter:      ${FILTER:-<none>}"
    echo "  Dry Run:     $DRY_RUN"
    echo

    # Check requirements
    check_requirements

    # Validate input directory
    if [[ ! -d "$input_dir" ]]; then
        print_error "Input directory not found: $input_dir"
        print_info "Run save-images.sh on an online machine first to create image archives"
        exit 1
    fi

    # Find all .tar files
    if [[ -n "$FILTER" ]]; then
        mapfile -t tar_files < <(find "$input_dir" -maxdepth 1 -name "*.tar" -type f | grep -i "$FILTER" | sort)
    else
        mapfile -t tar_files < <(find "$input_dir" -maxdepth 1 -name "*.tar" -type f | sort)
    fi
    local total=${#tar_files[@]}

    if [[ $total -eq 0 ]]; then
        if [[ -n "$FILTER" ]]; then
            print_error "No .tar files matching '$FILTER' in $input_dir"
        else
            print_error "No .tar files found in $input_dir"
            print_info "Run save-images.sh on an online machine first to create image archives"
        fi
        exit 1
    fi

    print_success "Found $total image archive(s) in $input_dir"
    echo

    # Show file list
    print_info "Archives to load:"
    for tar_file in "${tar_files[@]}"; do
        local file_size
        file_size=$(du -h "$tar_file" | cut -f1)
        echo "  - $(basename "$tar_file")  ($file_size)"
    done
    echo

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "This is a DRY RUN - no changes will be made"
        print_summary "$input_dir" "0 (dry run)" "$total"
        return 0
    fi

    # Load each image
    local current=0
    local loaded=0
    local failed=0

    for tar_file in "${tar_files[@]}"; do
        ((current++)) || true
        local filename
        filename=$(basename "$tar_file")
        local file_size
        file_size=$(du -h "$tar_file" | cut -f1)

        echo -e "${BLUE}[$current/$total]${NC} Loading: $filename ($file_size)"

        local load_output
        if load_output=$(docker load -i "$tar_file" 2>&1); then
            echo "$load_output" | while IFS= read -r line; do
                print_info "  $line"
            done
            print_success "  Loaded successfully"
            ((loaded++)) || true
        else
            echo "$load_output" | while IFS= read -r line; do
                print_info "  $line"
            done
            print_error "  Failed to load $filename"
            ((failed++)) || true
        fi

        echo
    done

    # Print summary
    if [[ $failed -gt 0 ]]; then
        print_warning "$failed image(s) failed to load"
    fi

    print_summary "$input_dir" "$loaded" "$total"
}

# Run main function
main "$@"

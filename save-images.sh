#!/bin/bash
################################################################################
# Docker Image Save Script
#
# Purpose: On an ONLINE machine, pull and save all Docker images from
#          docker-compose.yml to .tar files for transfer to offline systems.
#
# Usage: ./save-images.sh [OPTIONS] [OUTPUT_DIR]
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
DEFAULT_OUTPUT="./docker-images"
DRY_RUN=false
COMPOSE_FILE="docker-compose.yml"
FILTER=""

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Docker Image Save - Mystic Home Server${NC}"
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

Pull and save all Docker images from docker-compose.yml to .tar files for
transfer to offline/air-gapped systems.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be saved without making changes
    -f, --file FILE     Specify docker-compose file (default: docker-compose.yml)
    --filter PATTERN    Only save images matching PATTERN (grep -i, e.g. "jenkins")

ARGUMENTS:
    OUTPUT_DIR          Directory to save .tar files (default: ./docker-images/)

EXAMPLES:
    # Dry run to see what images would be saved
    ./save-images.sh --dry-run

    # Save all images to default directory
    ./save-images.sh

    # Save to a custom directory
    ./save-images.sh /mnt/usb/docker-images

    # Save only a specific image
    ./save-images.sh --filter jenkins

    # Use a different compose file
    ./save-images.sh -f docker-compose.prod.yml

NOTES:
    - Requires internet access to pull images
    - Requires Docker to be installed and running
    - Image filenames replace / and : with _ (e.g. ollama_ollama_latest.tar)
    - Existing .tar files will be overwritten

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

extract_images() {
    # Extract all image: values from docker-compose.yml, deduplicate
    grep -E '^\s+image:\s+' "$COMPOSE_FILE" | \
        sed -E 's/^\s+image:\s+//' | \
        tr -d ' ' | \
        sort -u
}

image_to_filename() {
    # Convert image name to safe filename: replace / and : with _
    local image="$1"
    echo "${image//[\/:]/_}.tar"
}

print_summary() {
    local output_dir="$1"
    local saved_count="$2"
    local total_count="$3"

    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Save Complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Output Dir:     ${BLUE}$output_dir${NC}"
    echo -e "Images Saved:   ${BLUE}$saved_count / $total_count${NC}"

    if [[ "$DRY_RUN" == false ]] && [[ -d "$output_dir" ]]; then
        local total_size
        total_size=$(du -sh "$output_dir" 2>/dev/null | cut -f1)
        echo -e "Total Size:     ${BLUE}$total_size${NC}"
    fi

    echo
    print_info "Next steps:"
    echo "  1. Copy the $output_dir directory to portable media"
    echo "  2. Transfer to the offline/air-gapped machine"
    echo "  3. Run ./load-images.sh to import the images"
    echo
}

################################################################################
# Main Script
################################################################################

main() {
    local output_dir="$DEFAULT_OUTPUT"

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
            -f|--file)
                COMPOSE_FILE="$2"
                shift 2
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
                output_dir="$1"
                shift
                ;;
        esac
    done

    # Print header
    print_header
    echo

    # Show configuration
    print_info "Configuration:"
    echo "  Output Dir:    $output_dir"
    echo "  Compose File:  $COMPOSE_FILE"
    echo "  Filter:        ${FILTER:-<none>}"
    echo "  Dry Run:       $DRY_RUN"
    echo

    # Check requirements
    check_requirements

    # Extract images from docker-compose.yml
    images=$(extract_images)

    # Apply filter if specified
    if [[ -n "$FILTER" ]]; then
        images=$(echo "$images" | grep -i "$FILTER" || true)
        if [[ -z "$images" ]]; then
            print_error "No images matching filter '$FILTER'"
            exit 1
        fi
    fi

    image_count=$(echo "$images" | wc -l)

    print_success "Found $image_count unique images in $COMPOSE_FILE"
    echo

    # Show image list
    print_info "Images to save:"
    while IFS= read -r image; do
        local filename
        filename=$(image_to_filename "$image")
        echo "  - $image  ->  $filename"
    done <<< "$images"
    echo

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "This is a DRY RUN - no changes will be made"
        print_summary "$output_dir" "0 (dry run)" "$image_count"
        return 0
    fi

    # Create output directory
    mkdir -p "$output_dir"
    print_success "Output directory ready: $output_dir"
    echo

    # Pull and save each image
    local current=0
    local saved=0
    local failed=0

    while IFS= read -r image; do
        ((current++)) || true
        local filename
        filename=$(image_to_filename "$image")

        echo -e "${BLUE}[$current/$image_count]${NC} Processing: $image"

        # Pull the image
        print_info "  Pulling..."
        if docker pull "$image" > /dev/null 2>&1; then
            print_success "  Pulled successfully"
        else
            print_error "  Failed to pull $image"
            ((failed++)) || true
            continue
        fi

        # Save the image to tar
        print_info "  Saving to $filename..."
        if docker save -o "$output_dir/$filename" "$image"; then
            local file_size
            file_size=$(du -h "$output_dir/$filename" | cut -f1)
            print_success "  Saved ($file_size)"
            ((saved++)) || true
        else
            print_error "  Failed to save $image"
            ((failed++)) || true
        fi

        echo
    done <<< "$images"

    # Print summary
    if [[ $failed -gt 0 ]]; then
        print_warning "$failed image(s) failed to save"
    fi

    print_summary "$output_dir" "$saved" "$image_count"
}

# Run main function
main "$@"

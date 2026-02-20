#!/bin/bash
################################################################################
# Mystic Home Server - Bundle Script
#
# Purpose: Package selected services (images + volumes + repo files) into a
#          self-contained directory for transfer to an offline machine.
#
# Usage: sudo ./scripts/bundle.sh [OPTIONS] OUTPUT_DIR
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
DRY_RUN=false
BUNDLE_ALL=false
SERVICES=""
SKIP_IMAGES=false
SKIP_VOLUMES=false
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

# All known service volume directory names (top-level dirs under MYSTIC_ROOT)
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
    echo -e "${BLUE}  Service Bundle - Mystic Home Server${NC}"
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
Usage: $0 [OPTIONS] OUTPUT_DIR

Package selected services (images + volumes + repo files) into a self-contained
directory for transfer to an offline/air-gapped machine.

OPTIONS:
    -h, --help                      Show this help message
    -d, --dry-run                   Show what would be bundled without changes
    --all                           Bundle all services
    --services SERVICE1,SERVICE2    Bundle only specific services (comma-separated)
    --skip-images                   Skip saving Docker images
    --skip-volumes                  Skip exporting volume data

ARGUMENTS:
    OUTPUT_DIR      Directory to create the bundle in (required)

AVAILABLE SERVICES:
    traefik, gateway, nextcloud, mariadbone, jenkins, bamboo, postgresdbfive,
    confluence, postgresdbone, jira, postgresdbtwo, bitbucket, postgresdbthree,
    postgresdbfour, mailserver, mattermost, ollama, openwebui, elasticsearch,
    logstash, kibana

EXAMPLES:
    # Bundle everything for full offline deployment
    sudo ./scripts/bundle.sh --all /mnt/usb/mystic

    # Bundle only selected services
    sudo ./scripts/bundle.sh --services traefik,gateway,jenkins,ollama /mnt/usb/mystic

    # Dry run to see what would be bundled
    sudo ./scripts/bundle.sh --dry-run --all /mnt/usb/mystic

    # Bundle repo files and images only (no volume data)
    sudo ./scripts/bundle.sh --skip-volumes --all /mnt/usb/mystic

NOTES:
    - Must be run as root to preserve file ownership in volume exports
    - Containers for exported services will be stopped during volume archiving
    - The output directory will contain everything needed for offline deployment

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

    # Check Docker is running
    if ! docker info &> /dev/null 2>&1; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    print_success "Docker daemon is running"

    # Check for docker-compose.yml
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_error "Docker compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    print_success "Found $COMPOSE_FILE"

    echo
}

extract_service_images() {
    # Parse docker-compose.yml to build service_name -> image mapping
    # Returns lines of "service_name image_name"
    local current_service=""
    while IFS= read -r line; do
        # Service definition: exactly 2-space indent, name followed by colon
        if [[ "$line" =~ ^\ \ ([a-zA-Z][a-zA-Z0-9_-]+):$ ]]; then
            current_service="${BASH_REMATCH[1]}"
        fi
        # Image line: 4+ space indent
        if [[ -n "$current_service" ]] && [[ "$line" =~ ^\ +image:\ +(.+)$ ]]; then
            echo "$current_service ${BASH_REMATCH[1]}"
            current_service=""
        fi
    done < "$COMPOSE_FILE"
}

image_to_filename() {
    # Convert image name to safe filename: replace / and : with _
    local image="$1"
    echo "${image//[\/:]/_}.tar"
}

copy_repo_files() {
    local output_dir="$1"

    echo
    echo -e "${BLUE}--- Copying repo files ---${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would copy repo files to $output_dir/"
        for f in docker-compose.yml .env.example README.md CLAUDE.md LICENSE; do
            if [[ -f "$PROJECT_DIR/$f" ]]; then
                print_info "  $f"
            fi
        done
        if [[ -d "$PROJECT_DIR/config" ]]; then
            print_info "  config/ (directory)"
        fi
        if [[ -d "$PROJECT_DIR/scripts" ]]; then
            print_info "  scripts/ (directory)"
        fi
        return 0
    fi

    mkdir -p "$output_dir"

    # Copy individual repo files
    for f in docker-compose.yml .env.example README.md CLAUDE.md LICENSE; do
        if [[ -f "$PROJECT_DIR/$f" ]]; then
            cp "$PROJECT_DIR/$f" "$output_dir/"
            print_success "Copied $f"
        else
            print_warning "Not found (skipping): $f"
        fi
    done

    # Copy config directory (traefik.toml, logstash pipeline, etc.)
    if [[ -d "$PROJECT_DIR/config" ]]; then
        cp -r "$PROJECT_DIR/config" "$output_dir/"
        print_success "Copied config/"
    else
        print_warning "Not found (skipping): config/"
    fi

    # Copy scripts directory (all .sh files)
    if [[ -d "$PROJECT_DIR/scripts" ]]; then
        mkdir -p "$output_dir/scripts"
        cp "$PROJECT_DIR/scripts/"*.sh "$output_dir/scripts/"
        chmod +x "$output_dir/scripts/"*.sh
        print_success "Copied scripts/"
    else
        print_warning "Not found (skipping): scripts/"
    fi
}

save_images() {
    local output_dir="$1"
    shift
    local services=("$@")

    echo
    echo -e "${BLUE}--- Saving Docker images ---${NC}"

    if [[ "$SKIP_IMAGES" == true ]]; then
        print_warning "Skipping image save (--skip-images)"
        return 0
    fi

    # Build the service->image mapping from docker-compose.yml
    local -A service_image_map
    while IFS=' ' read -r svc img; do
        service_image_map["$svc"]="$img"
    done < <(extract_service_images)

    # Collect unique images for the selected services
    local -A images_to_save
    local missing_images=()

    for svc in "${services[@]}"; do
        local img="${service_image_map[$svc]:-}"
        if [[ -z "$img" ]]; then
            print_warning "No image found for service: $svc (skipping image save for this service)"
            missing_images+=("$svc")
            continue
        fi
        images_to_save["$img"]=1
    done

    local image_list=()
    for img in "${!images_to_save[@]}"; do
        image_list+=("$img")
    done

    if [[ ${#image_list[@]} -eq 0 ]]; then
        print_warning "No images to save"
        return 0
    fi

    local image_dir="$output_dir/docker-images"
    local total=${#image_list[@]}
    local current=0
    local saved=0

    print_info "Images to save ($total):"
    for img in "${image_list[@]}"; do
        local filename
        filename=$(image_to_filename "$img")
        echo "  - $img  ->  $filename"
    done
    echo

    if [[ "$DRY_RUN" == true ]]; then
        for img in "${image_list[@]}"; do
            ((current++)) || true
            print_info "[DRY RUN] Would pull and save: $img"
        done
        return 0
    fi

    mkdir -p "$image_dir"

    for img in "${image_list[@]}"; do
        ((current++)) || true
        local filename
        filename=$(image_to_filename "$img")

        echo -e "${BLUE}[$current/$total]${NC} Processing: $img"

        # Pull the image
        print_info "  Pulling..."
        if docker pull "$img" > /dev/null 2>&1; then
            print_success "  Pulled successfully"
        else
            print_error "  Failed to pull $img"
            continue
        fi

        # Save the image to tar
        print_info "  Saving to $filename..."
        if docker save -o "$image_dir/$filename" "$img"; then
            local file_size
            file_size=$(du -h "$image_dir/$filename" | cut -f1)
            print_success "  Saved ($file_size)"
            ((saved++)) || true
        else
            print_error "  Failed to save $img"
            rm -f "$image_dir/$filename"
        fi

        echo
    done

    print_success "Saved $saved / $total images"
}

export_volumes() {
    local output_dir="$1"
    shift
    local services=("$@")

    echo
    echo -e "${BLUE}--- Exporting volumes ---${NC}"

    if [[ "$SKIP_VOLUMES" == true ]]; then
        print_warning "Skipping volume export (--skip-volumes)"
        return 0
    fi

    local comma_list
    comma_list=$(IFS=','; echo "${services[*]}")

    local volume_dir="$output_dir/volume-exports"
    local root_path="${MYSTIC_ROOT:-.}"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] Would export volumes for: $comma_list"
        print_info "  Volume root: $root_path"
        print_info "  Output: $volume_dir"
        return 0
    fi

    mkdir -p "$volume_dir"

    # Call export-volumes.sh with the selected services
    "$SCRIPT_DIR/export-volumes.sh" \
        --services "$comma_list" \
        --force \
        --root "$root_path" \
        "$volume_dir"
}

print_summary() {
    local output_dir="$1"
    shift
    local services=("$@")

    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Bundle Complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Output Dir:       ${BLUE}$output_dir${NC}"
    echo -e "Services:         ${BLUE}${services[*]}${NC}"

    if [[ "$SKIP_IMAGES" == true ]]; then
        echo -e "Images:           ${YELLOW}skipped${NC}"
    else
        echo -e "Images:           ${GREEN}included${NC}"
    fi

    if [[ "$SKIP_VOLUMES" == true ]]; then
        echo -e "Volumes:          ${YELLOW}skipped${NC}"
    else
        echo -e "Volumes:          ${GREEN}included${NC}"
    fi

    if [[ "$DRY_RUN" == false ]] && [[ -d "$output_dir" ]]; then
        local total_size
        total_size=$(du -sh "$output_dir" 2>/dev/null | cut -f1)
        echo -e "Total Size:       ${BLUE}$total_size${NC}"

        echo
        print_info "Bundle contents:"
        if [[ -f "$output_dir/docker-compose.yml" ]]; then
            echo "  docker-compose.yml"
        fi
        if [[ -f "$output_dir/.env.example" ]]; then
            echo "  .env.example"
        fi
        if [[ -d "$output_dir/config" ]]; then
            echo "  config/"
        fi
        if [[ -d "$output_dir/scripts" ]]; then
            echo "  scripts/"
        fi
        if [[ -d "$output_dir/docker-images" ]]; then
            local image_count
            image_count=$(find "$output_dir/docker-images" -name '*.tar' 2>/dev/null | wc -l)
            echo "  docker-images/ ($image_count image archives)"
        fi
        if [[ -d "$output_dir/volume-exports" ]]; then
            local volume_count
            volume_count=$(find "$output_dir/volume-exports" -name '*.tar.gz' 2>/dev/null | wc -l)
            echo "  volume-exports/ ($volume_count volume archives)"
        fi
    fi

    echo
    print_info "To deploy on the offline machine:"
    echo "  1. Copy this directory to the target machine"
    echo "  2. cd into the directory"
    echo "  3. Run: sudo scripts/deploy.sh"
    echo
}

################################################################################
# Main Script
################################################################################

main() {
    local output_dir=""

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
            --all)
                BUNDLE_ALL=true
                shift
                ;;
            --services)
                SERVICES="$2"
                shift 2
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
                echo
                usage
                ;;
            *)
                output_dir="$1"
                shift
                ;;
        esac
    done

    # Validate that either --all or --services is specified
    if [[ "$BUNDLE_ALL" == false ]] && [[ -z "$SERVICES" ]]; then
        print_error "You must specify either --all or --services SERVICE1,SERVICE2,..."
        echo
        usage
    fi

    # Validate OUTPUT_DIR is specified
    if [[ -z "$output_dir" ]]; then
        print_error "You must specify an output directory"
        echo
        usage
    fi

    # Print header
    print_header
    echo

    # Build the list of services to bundle
    local services_to_bundle=()

    if [[ "$BUNDLE_ALL" == true ]]; then
        services_to_bundle=("${ALL_SERVICES[@]}")
    else
        IFS=',' read -ra services_to_bundle <<< "$SERVICES"
    fi

    # Validate service names
    for svc in "${services_to_bundle[@]}"; do
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
    echo "  Output Dir:    $output_dir"
    echo "  Services:      ${services_to_bundle[*]}"
    echo "  Skip Images:   $SKIP_IMAGES"
    echo "  Skip Volumes:  $SKIP_VOLUMES"
    echo "  Dry Run:       $DRY_RUN"
    echo

    # Check requirements
    check_requirements

    # Step 1: Copy repo files
    copy_repo_files "$output_dir"

    # Step 2: Save Docker images for selected services
    save_images "$output_dir" "${services_to_bundle[@]}"

    # Step 3: Export volumes for selected services
    export_volumes "$output_dir" "${services_to_bundle[@]}"

    # Step 4: Print summary
    print_summary "$output_dir" "${services_to_bundle[@]}"

    if [[ "$DRY_RUN" == true ]]; then
        echo
        print_warning "This was a DRY RUN - no changes were made"
        print_info "Run without --dry-run to create the bundle"
        echo
    fi
}

# Run main function
main "$@"

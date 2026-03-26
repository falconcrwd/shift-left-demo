#!/bin/bash
#
# Standalone FCS CLI downloader using the v2 API endpoint.
#
# This script downloads and installs the CrowdStrike FCS CLI tool independently
# of GitHub Actions. Required environment variables must be provided.
#
# Required Environment Variables:
#   FCS_CLIENT_ID      - CrowdStrike API Client ID
#   FCS_CLIENT_SECRET  - CrowdStrike API Client Secret
#
# Optional Environment Variables:
#   FALCON_REGION         - CrowdStrike region (default: us-1)
#   FCS_VERSION          - Specific FCS version to download (default: latest)
#   FCS_BIN_PATH         - Directory to install FCS binary (default: ~/.local/bin)
#

set -euo pipefail

# Configuration
TEMP_DIR=$(mktemp -d)
readonly TEMP_DIR
trap 'rm -rf "$TEMP_DIR"' EXIT

# Default values
DEFAULT_REGION="us-1"
DEFAULT_BIN_PATH="$HOME/.local/bin"

# Function to show usage
show_usage() {
    cat << 'EOF'
Usage: fcs_download_standalone.sh [OPTIONS]

Downloads and installs CrowdStrike FCS CLI tool.

Required Environment Variables:
  FCS_CLIENT_ID      CrowdStrike API Client ID
  FCS_CLIENT_SECRET  CrowdStrike API Client Secret

Optional Environment Variables:
  FALCON_REGION         CrowdStrike region (default: us-1)
                        Valid values: us-1, us-2, eu-1, us-gov-1, us-gov-2
  FCS_VERSION          Specific FCS version to download (default: latest)
  FCS_BIN_PATH         Directory to install FCS binary (default: ~/.local/bin)

Options:
  -h, --help           Show this help message
  -v, --version        Show version info for downloaded FCS

Examples:
  # Basic usage with environment variables set
  export FCS_CLIENT_ID="your-client-id"
  export FCS_CLIENT_SECRET="your-client-secret"
  ./fcs_download_standalone.sh

  # With specific region and version
  export FCS_CLIENT_ID="your-client-id"
  export FCS_CLIENT_SECRET="your-client-secret"
  export FALCON_REGION="eu-1"
  export FCS_VERSION="2.1.0"
  ./fcs_download_standalone.sh

  # With custom installation path
  export FCS_CLIENT_ID="your-client-id"
  export FCS_CLIENT_SECRET="your-client-secret"
  export FCS_BIN_PATH="/usr/local/bin"
  ./fcs_download_standalone.sh

EOF
}

# Function to get API base URL for region
get_region_base_url() {
    local region="$1"
    case "$region" in
        "us-1") echo "api.crowdstrike.com" ;;
        "us-2") echo "api.us-2.crowdstrike.com" ;;
        "eu-1") echo "api.eu-1.crowdstrike.com" ;;
        "us-gov-1") echo "api.laggar.gcw.crowdstrike.com" ;;
        "us-gov-2") echo "api.us-gov-2.crowdstrike.mil" ;;
        *) echo "api.crowdstrike.com" ;;
    esac
}

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

# Function to get OAuth2 token
get_oauth_token() {
    local client_id="$1"
    local client_secret="$2"
    local base_url="$3"

    local token_response
    token_response=$(curl -s -X POST "https://${base_url}/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${client_id}&client_secret=${client_secret}&grant_type=client_credentials")

    if ! echo "$token_response" | jq -e '.access_token' > /dev/null 2>&1; then
        log_error "Failed to get OAuth token"
        log_error "Response: $token_response"
        return 1
    fi

    echo "$token_response" | jq -r '.access_token'
}

# Function to detect OS and architecture separately
detect_platform() {
    local system
    local machine
    system=$(uname -s | tr '[:upper:]' '[:lower:]')
    machine=$(uname -m | tr '[:upper:]' '[:lower:]')

    local os arch

    case "$system" in
        linux)
            os="linux"
            ;;
        darwin)
            os="darwin"
            ;;
        mingw*|cygwin*|msys*)
            os="windows"
            ;;
        *)
            log_warn "Unknown system: $system, defaulting to linux"
            os="linux"
            ;;
    esac

    case "$machine" in
        aarch64|arm64) arch="arm64" ;;
        x86_64|amd64) arch="amd64" ;;
        *)
            log_warn "Unknown architecture: $machine, defaulting to amd64"
            arch="amd64"
            ;;
    esac

    echo "${os} ${arch}"
}

# Function to call the v2 files-download API
get_fcs_download_info() {
    local token="$1"
    local base_url="$2"
    local platform="$3"
    local version="$4"

    # Parse OS and architecture from platform
    local os
    local arch
    os=$(echo "$platform" | cut -d' ' -f1)
    arch=$(echo "$platform" | cut -d' ' -f2)

    local api_url="https://${base_url}/csdownloads/combined/files-download/v2"
    local filter

    # Build filter parameter
    if [[ -n "$version" ]]; then
        filter="category:'fcs'+os:'${os}'+arch:'${arch}'+file_version:'${version}'"
    else
        filter="category:'fcs'+os:'${os}'+arch:'${arch}'"
    fi

    # Simple URL encoding for the filter
    local encoded_filter
    encoded_filter=$(echo "$filter" | sed "s/+/%2B/g; s/:/%3A/g; s/'/%27/g")

    local response
    response=$(curl -s -X GET "$api_url?filter=${encoded_filter}&limit=100&sort=file_version%7Cdesc" \
        -H "accept: application/json" \
        -H "Authorization: Bearer $token")

    # Check if response contains errors
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        log_error "API returned errors:"
        echo "$response" | jq -r '.errors[] | "  - \(.message)"'
        return 1
    fi

    # Check if we have resources
    if ! echo "$response" | jq -e '.resources[0]' > /dev/null 2>&1; then
        log_error "No resources found in API response"
        log_error "Response: $response"
        return 1
    fi

    echo "$response"
}

# Function to extract download info from API response (gets latest version)
extract_download_details() {
    local response="$1"
    local detail_type="$2"  # download_url, file_name, file_hash, version

    # API returns results sorted by file_version:desc, so first element is the latest
    case "$detail_type" in
        "download_url")
            echo "$response" | jq -r ".resources[0].download_info.download_url // empty"
            ;;
        "file_name")
            echo "$response" | jq -r ".resources[0].file_name // empty"
            ;;
        "file_hash")
            echo "$response" | jq -r ".resources[0].download_info.file_hash // .resources[0].file_hash // empty"
            ;;
        "version")
            echo "$response" | jq -r ".resources[0].file_version // empty"
            ;;
        *)
            echo "$response" | jq -r ".resources[0].$detail_type // empty"
            ;;
    esac
}

# Function to download file with hash validation
download_and_validate_file() {
    local download_url="$1"
    local file_name="$2"
    local expected_hash="$3"
    local output_dir="$4"

    local output_path="$output_dir/$file_name"

    log_info "Downloading $file_name..."
    if ! curl -L -o "$output_path" "$download_url"; then
        log_error "Download failed"
        return 1
    fi

    log_info "Validating file integrity..."
    local file_hash
    if command -v sha256sum > /dev/null; then
        file_hash=$(sha256sum "$output_path" | cut -d' ' -f1)
    elif command -v shasum > /dev/null; then
        file_hash=$(shasum -a 256 "$output_path" | cut -d' ' -f1)
    else
        log_error "No SHA256 utility available"
        return 1
    fi

    # Convert hashes to lowercase for comparison
    local file_hash_lower
    local expected_hash_lower
    file_hash_lower=$(echo "$file_hash" | tr '[:upper:]' '[:lower:]')
    expected_hash_lower=$(echo "$expected_hash" | tr '[:upper:]' '[:lower:]')

    if [[ "$file_hash_lower" == "$expected_hash_lower" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} File hash validated successfully" >&2
        echo "$output_path"
        return 0
    else
        log_error "Hash mismatch!"
        log_error "Expected: $expected_hash"
        log_error "Got:      $file_hash"
        return 1
    fi
}

# Function to extract and setup FCS binary
extract_and_setup_fcs() {
    local archive_path="$1"
    local bin_path="$2"

    # Create bin directory
    mkdir -p "$bin_path"

    local fcs_binary="fcs"
    if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == CYGWIN* || "$(uname -s)" == MSYS* ]]; then
        fcs_binary="fcs.exe"
    fi

    local fcs_path="$bin_path/$fcs_binary"

    log_info "Extracting FCS binary..."

    # Extract based on file extension
    if [[ "$archive_path" == *.tar.gz ]]; then
        # Extract tar.gz

        if ! tar -xzf "$archive_path" -C "$TEMP_DIR"; then
            log_error "Failed to extract tar.gz file"
            log_error "DEBUG: tar command failed for: '$archive_path'"
            return 1
        fi

        # Find the fcs binary
        local extracted_fcs
        extracted_fcs=$(find "$TEMP_DIR" -name "fcs" -o -name "fcs.exe" | head -n1)

        if [[ -z "$extracted_fcs" ]]; then
            log_error "FCS binary not found in archive"
            return 1
        fi

        cp "$extracted_fcs" "$fcs_path"

    elif [[ "$archive_path" == *.zip ]]; then
        # Extract zip
        if ! unzip -q "$archive_path" -d "$TEMP_DIR"; then
            log_error "Failed to extract zip file"
            return 1
        fi

        # Find the fcs binary
        local extracted_fcs
        extracted_fcs=$(find "$TEMP_DIR" -name "fcs" -o -name "fcs.exe" | head -n1)

        if [[ -z "$extracted_fcs" ]]; then
            log_error "FCS binary not found in archive"
            return 1
        fi

        cp "$extracted_fcs" "$fcs_path"
    else
        log_error "Unsupported archive format: $archive_path"
        return 1
    fi

    # Make executable on Unix-like systems
    if [[ "$(uname -s)" != MINGW* && "$(uname -s)" != CYGWIN* && "$(uname -s)" != MSYS* ]]; then
        chmod +x "$fcs_path"
    fi

    # Create log directory that FCS expects
    local log_dir="$HOME/.crowdstrike/log"
    mkdir -p "$log_dir"

    log_success "FCS binary ready at: $fcs_path"
    echo "$fcs_path"
}

# Function to add directory to PATH if not already present
add_to_path() {
    local bin_dir="$1"

    # Check if directory is already in PATH
    if [[ ":$PATH:" == *":$bin_dir:"* ]]; then
        log_info "Directory $bin_dir is already in PATH"
        return 0
    fi

    # Determine shell profile file
    local profile_file=""
    if [[ -n "${BASH_VERSION:-}" ]]; then
        if [[ -f "$HOME/.bashrc" ]]; then
            profile_file="$HOME/.bashrc"
        elif [[ -f "$HOME/.bash_profile" ]]; then
            profile_file="$HOME/.bash_profile"
        fi
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        if [[ -f "$HOME/.zshrc" ]]; then
            profile_file="$HOME/.zshrc"
        fi
    fi

    if [[ -n "$profile_file" ]]; then
        log_info "Adding $bin_dir to PATH in $profile_file"
        echo "export PATH=\"$bin_dir:\$PATH\"" >> "$profile_file"
        log_info "Please run 'source $profile_file' or restart your shell to update PATH"
    else
        log_warn "Could not determine shell profile file"
        log_warn "Please manually add $bin_dir to your PATH"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                # This will be handled after download
                SHOW_VERSION=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"

    log_info "============================================================"
    log_info "CrowdStrike FCS Standalone Downloader (v2 API)"
    log_info "============================================================"

    # Get configuration from environment variables
    local bin_path="${FCS_BIN_PATH:-$DEFAULT_BIN_PATH}"
    local client_id="${FCS_CLIENT_ID:-}"
    local client_secret="${FCS_CLIENT_SECRET:-}"
    local region="${FALCON_REGION:-$DEFAULT_REGION}"
    local version="${FCS_VERSION:-}"

    # Validate required inputs
    if [[ -z "$client_id" ]]; then
        log_error "FCS_CLIENT_ID environment variable is required"
        log_error ""
        log_error "Please set it with:"
        log_error "  export FCS_CLIENT_ID=\"your-client-id\""
        log_error ""
        log_error "Use --help for more information"
        exit 1
    fi

    if [[ -z "$client_secret" ]]; then
        log_error "FCS_CLIENT_SECRET environment variable is required"
        log_error ""
        log_error "Please set it with:"
        log_error "  export FCS_CLIENT_SECRET=\"your-client-secret\""
        log_error ""
        log_error "Use --help for more information"
        exit 1
    fi

    # Validate region
    case "$region" in
        us-1|us-2|eu-1|us-gov-1|us-gov-2) ;;
        *)
            log_warn "Unknown region '$region', using default 'us-1'"
            region="us-1"
            ;;
    esac

    # Get API base URL
    local base_url
    base_url=$(get_region_base_url "$region")

    log_info "Configuration:"
    log_info "   Region: $region"
    log_info "   Base URL: $base_url"
    log_info "   Version: ${version:-latest}"
    log_info "   Install Path: $bin_path"

    # Check required tools
    for tool in curl jq tar unzip; do
        if ! command -v "$tool" > /dev/null; then
            log_error "Required tool not found: $tool"
            log_error "Please install $tool and try again"
            exit 1
        fi
    done

    # Step 1: Get OAuth token
    log_info "Authenticating with CrowdStrike API..."
    local token
    if ! token=$(get_oauth_token "$client_id" "$client_secret" "$base_url"); then
        log_error "Failed to get OAuth token"
        exit 1
    fi

    # Step 2: Detect platform
    local platform
    platform=$(detect_platform)
    log_info "Detected platform: $platform"

    # Step 3: Get download info from v2 API
    log_info "Fetching FCS download information..."
    local download_response
    if ! download_response=$(get_fcs_download_info "$token" "$base_url" "$platform" "$version"); then
        log_error "Failed to get FCS download information"
        exit 1
    fi

    # Step 4: Extract download details
    local download_url file_name file_hash file_version
    download_url=$(extract_download_details "$download_response" "download_url")
    file_name=$(extract_download_details "$download_response" "file_name")
    file_hash=$(extract_download_details "$download_response" "file_hash")
    file_version=$(extract_download_details "$download_response" "version")

    if [[ -z "$download_url" || -z "$file_name" || -z "$file_hash" ]]; then
        log_error "Missing required download details"
        log_error "Download URL: $download_url"
        log_error "File Name: $file_name"
        log_error "File Hash: $file_hash"
        exit 1
    fi

    log_info "Found FCS version: ${file_version:-unknown}"

    # Step 5: Download and validate file
    local downloaded_file
    if ! downloaded_file=$(download_and_validate_file "$download_url" "$file_name" "$file_hash" "$TEMP_DIR"); then
        log_error "Failed to download or validate FCS file"
        exit 1
    fi

    # Step 6: Extract and setup FCS binary
    local fcs_binary_path
    if ! fcs_binary_path=$(extract_and_setup_fcs "$downloaded_file" "$bin_path"); then
        log_error "Failed to extract and setup FCS binary"
        exit 1
    fi

    # Step 7: Add to PATH if not already present
    if [[ "$bin_path" != "/usr/local/bin" && "$bin_path" != "/usr/bin" ]]; then
        add_to_path "$bin_path"
    fi

    # Show version if requested
    if [[ "${SHOW_VERSION:-}" == "true" ]]; then
        log_info ""
        log_info "FCS Version Information:"
        if "$fcs_binary_path" --version 2>/dev/null; then
            true  # Version command succeeded
        else
            log_warn "Could not retrieve version information"
        fi
    fi

    log_success ""
    log_success "FCS download and installation completed successfully!"
    log_success "FCS binary: $fcs_binary_path"
    log_success "Version: ${file_version:-unknown}"
    log_success ""
    log_success "You can now use FCS with: fcs --help"
    log_success ""
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
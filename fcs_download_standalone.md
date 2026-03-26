# FCS Download Standalone

A standalone version of the CrowdStrike FCS CLI downloader script, refactored from the original GitHub Actions version for independent use.

## Overview

`fcs_download_standalone.sh` downloads and installs the CrowdStrike FCS CLI tool using the v2 API endpoint. This script has been adapted from the original GitHub Actions script to work independently on any bash-compatible system.

## Key Modifications

### 1. **Removed GitHub Actions Dependencies**
- Removed `set_github_output()` function and related GitHub Actions output handling
- Removed `GITHUB_PATH` and `GITHUB_OUTPUT` environment variable usage
- Removed GitHub Actions specific environment variables like `INPUT_*` and `RUNNER_TEMP`

### 2. **Enhanced Environment Variable Handling**
Changed to use standard environment variables:
- `FCS_CLIENT_ID` (required)
- `FCS_CLIENT_SECRET` (required)
- `FALCON_REGION` (optional, defaults to "us-1")
- `FCS_VERSION` (optional, defaults to latest)
- `FCS_BIN_PATH` (optional, defaults to `~/.local/bin`)

### 3. **Added User-Friendly Features**
- **Help system**: Added `--help` flag with comprehensive usage documentation
- **Command-line arguments**: Added argument parsing for `-h`, `--help`, `-v`, `--version`
- **Better error messages**: More helpful error messages with examples for setting environment variables
- **PATH management**: Automatically adds the installation directory to your shell profile

### 4. **Improved User Experience**
- **Better logging**: More informative progress messages during download and installation
- **Validation**: Better validation of region names with warnings for unknown regions
- **Installation feedback**: Shows where the binary was installed and how to use it

## Requirements

- **Operating System**: Linux, macOS, or Windows (with bash support)
- **Required Tools**: `curl`, `jq`, `tar`, `unzip`
- **CrowdStrike API Credentials**: Valid Client ID and Client Secret

## Automatic Platform Detection

The script **automatically detects your operating system and architecture** and downloads the appropriate FCS CLI binary without any manual configuration. This means:

### ✅ **Supported Platforms (Auto-Detected)**

**Operating Systems:**
- **Linux** - Automatically detected from `uname -s`
- **macOS** (Darwin) - Automatically detected from `uname -s`
- **Windows** - Detected via MinGW/Cygwin/MSYS environments

**Architectures:**
- **x86_64/AMD64** - Intel/AMD 64-bit processors
- **ARM64/AArch64** - ARM 64-bit processors (Apple Silicon, ARM servers)

### 🔄 **How It Works**

1. The script runs `uname -s` to detect your operating system
2. The script runs `uname -m` to detect your processor architecture
3. It automatically requests the correct FCS binary from the CrowdStrike API
4. Downloads and installs the platform-specific binary

**Example Detection Output:**
```
[INFO] Detected platform: linux amd64
[INFO] Detected platform: darwin arm64
[INFO] Detected platform: windows amd64
```

### ⚠️ **Important Notes**

- **No Cross-Platform Downloads**: The script downloads FCS for the platform you're currently running on. You cannot specify a different target platform.
- **Fallback Behavior**: If the system/architecture cannot be determined, it defaults to `linux amd64`
- **Windows Support**: Requires bash-compatible environment (Git Bash, WSL, Cygwin, etc.)

## Environment Variables

### Required Variables

| Variable | Description |
|----------|-------------|
| `FCS_CLIENT_ID` | CrowdStrike API Client ID |
| `FCS_CLIENT_SECRET` | CrowdStrike API Client Secret |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `FALCON_REGION` | CrowdStrike region | `us-1` |
| `FCS_VERSION` | Specific FCS version to download | `latest` |
| `FCS_BIN_PATH` | Directory to install FCS binary | `~/.local/bin` |

### Supported Regions

- `us-1` - US Commercial (default)
- `us-2` - US Commercial 2
- `eu-1` - European Union
- `us-gov-1` - US Government
- `us-gov-2` - US Government 2

## Usage Examples

### Basic Usage

```bash
# Set required environment variables
export FCS_CLIENT_ID="your-client-id"
export FCS_CLIENT_SECRET="your-client-secret"

# Run the script
./fcs_download_standalone.sh
```

### With Specific Region and Version

```bash
# Set environment variables with custom region and version
export FCS_CLIENT_ID="your-client-id"
export FCS_CLIENT_SECRET="your-client-secret"
export FALCON_REGION="eu-1"
export FCS_VERSION="2.1.0"

# Run the script
./fcs_download_standalone.sh
```

### With Custom Installation Path

```bash
# Install to system-wide location
export FCS_CLIENT_ID="your-client-id"
export FCS_CLIENT_SECRET="your-client-secret"
export FCS_BIN_PATH="/usr/local/bin"

# Run the script (may require sudo for system directories)
sudo -E ./fcs_download_standalone.sh
```

### Using Command Line Options

```bash
# Show help information
./fcs_download_standalone.sh --help

# Show version information after installation
./fcs_download_standalone.sh --version
```

### Complete Example with All Options

```bash
#!/bin/bash

# Set all configuration options
export FCS_CLIENT_ID="your-client-id-here"
export FCS_CLIENT_SECRET="your-client-secret-here"
export FALCON_REGION="us-2"
export FCS_VERSION="2.1.0"
export FCS_BIN_PATH="$HOME/bin"

# Create the bin directory if it doesn't exist
mkdir -p "$FCS_BIN_PATH"

# Download and install FCS
./fcs_download_standalone.sh --version

# Verify installation
fcs --help
```

## Installation Process

The script performs the following steps:

1. **Validation**: Checks for required environment variables and tools
2. **Authentication**: Obtains OAuth token from CrowdStrike API
3. **Platform Detection**: **Automatically determines your OS and architecture** using `uname`
4. **API Query**: Fetches download information for your specific platform using v2 API endpoint
5. **Download**: Downloads the correct FCS binary archive for your platform with progress indication
6. **Validation**: Verifies file integrity using SHA256 hash
7. **Extraction**: Extracts and installs the platform-appropriate FCS binary
8. **PATH Setup**: Optionally adds installation directory to shell profile

## Output

Upon successful completion, you'll see output similar to:

```
[INFO] ============================================================
[INFO] CrowdStrike FCS Standalone Downloader (v2 API)
[INFO] ============================================================
[INFO] Configuration:
[INFO]    Region: us-1
[INFO]    Base URL: api.crowdstrike.com
[INFO]    Version: latest
[INFO]    Install Path: /home/user/.local/bin
[INFO] Authenticating with CrowdStrike API...
[INFO] Detected platform: linux amd64
[INFO] Fetching FCS download information...
[INFO] Found FCS version: 2.2.0
[INFO] Downloading fcs_2.2.0_linux_amd64.tar.gz...
[INFO] Validating file integrity...
[SUCCESS] File hash validated successfully
[INFO] Extracting FCS binary...
[SUCCESS] FCS binary ready at: /home/user/.local/bin/fcs
[INFO] Adding /home/user/.local/bin to PATH in /home/user/.bashrc
[INFO] Please run 'source /home/user/.bashrc' or restart your shell to update PATH

[SUCCESS]
[SUCCESS] FCS download and installation completed successfully!
[SUCCESS] FCS binary: /home/user/.local/bin/fcs
[SUCCESS] Version: 2.2.0
[SUCCESS]
[SUCCESS] You can now use FCS with: fcs --help
[SUCCESS]
```

## Troubleshooting

### Common Issues

1. **Missing tools**: Install required dependencies (`curl`, `jq`, `tar`, `unzip`)
2. **Authentication errors**: Verify your Client ID and Client Secret are correct
3. **Permission errors**: Use appropriate permissions for the installation directory
4. **Network issues**: Ensure access to CrowdStrike API endpoints

### Getting Help

```bash
# Show detailed usage information
./fcs_download_standalone.sh --help
```

## Differences from GitHub Actions Version

| Feature | GitHub Actions | Standalone |
|---------|----------------|------------|
| Environment Variables | `INPUT_*` format | Standard format |
| Output Handling | GitHub Actions outputs | Direct console output |
| PATH Management | Automatic via `GITHUB_PATH` | Manual shell profile update |
| Error Handling | GitHub Actions workflow context | Standalone script context |
| Installation Location | `RUNNER_TEMP` | User-configurable |
| Help System | Not available | Built-in `--help` |

## Security Notes

- Store credentials securely and never commit them to version control
- Use environment variables or secure credential management systems
- Validate file hashes are checked automatically for integrity
- The script creates a temporary directory that is automatically cleaned up

## License

This script maintains the same license as the original FCS Action project.
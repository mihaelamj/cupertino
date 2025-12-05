#!/bin/bash
#
# Cupertino Installer
# One-command install for macOS
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/mihaelamj/cupertino/main/install.sh | bash
#
# Options:
#   --build    Force build from source instead of downloading binary
#
# What this script does:
#   1. Checks requirements (macOS 15+)
#   2. Downloads pre-built universal binary (or builds from source)
#   3. Installs to /usr/local/bin
#   4. Downloads documentation databases
#

set -e

# Configuration
REPO="mihaelamj/cupertino"
INSTALL_PATH="/usr/local/bin/cupertino"
FORCE_BUILD=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --build)
            FORCE_BUILD=true
            shift
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print with color
info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}==>${NC} $1"; exit 1; }

# Banner
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Cupertino Installer               ║${NC}"
echo -e "${GREEN}║      Apple Documentation MCP Server    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    error "Cupertino requires macOS. Detected: $(uname)"
fi

# Check macOS version (requires 15+)
MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MACOS_VERSION" -lt 15 ]]; then
    error "Cupertino requires macOS 15 (Sequoia) or later. Detected: $(sw_vers -productVersion)"
fi

# Check for existing installation
if [[ -f "$INSTALL_PATH" ]]; then
    EXISTING_VERSION=$("$INSTALL_PATH" --version 2>/dev/null || echo "unknown")
    warn "Existing installation found: $EXISTING_VERSION"
    read -p "Do you want to reinstall? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Installation cancelled."
        exit 0
    fi
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Get latest release version
info "Checking latest release..."
LATEST_VERSION=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_VERSION" ]]; then
    warn "Could not determine latest version, will build from source"
    FORCE_BUILD=true
else
    info "Latest version: $LATEST_VERSION"
fi

# Try to download pre-built binary
download_binary() {
    local BINARY_URL="https://github.com/${REPO}/releases/download/${LATEST_VERSION}/cupertino-${LATEST_VERSION}-macos-universal.tar.gz"

    info "Downloading pre-built binary..."
    if curl -sL --fail -o "$TEMP_DIR/cupertino.tar.gz" "$BINARY_URL" 2>/dev/null; then
        info "Extracting..."
        tar -xzf "$TEMP_DIR/cupertino.tar.gz" -C "$TEMP_DIR"
        if [[ -f "$TEMP_DIR/cupertino" ]]; then
            return 0
        fi
    fi
    return 1
}

# Build from source
build_from_source() {
    # Check Swift
    if ! command -v swift &> /dev/null; then
        error "Swift toolchain not found. Please install Xcode from the App Store."
    fi

    info "Found: $(swift --version 2>&1 | head -1)"

    info "Cloning repository..."
    git clone --depth 1 "https://github.com/${REPO}.git" "$TEMP_DIR/cupertino" 2>&1 | tail -1

    info "Building from source (this may take 1-2 minutes)..."
    cd "$TEMP_DIR/cupertino/Packages"
    swift build -c release 2>&1 | grep -E "(Build complete|Compiling|Linking|error:)" | tail -5

    if [[ -f ".build/release/cupertino" ]]; then
        cp ".build/release/cupertino" "$TEMP_DIR/cupertino-bin"
        mv "$TEMP_DIR/cupertino-bin" "$TEMP_DIR/cupertino"
        return 0
    fi
    return 1
}

# Install binary
if [[ "$FORCE_BUILD" == "true" ]]; then
    info "Building from source (--build flag)..."
    build_from_source || error "Build failed"
elif ! download_binary; then
    warn "Pre-built binary not available, building from source..."
    build_from_source || error "Build failed"
fi

success "Binary ready!"

# Install
info "Installing to $INSTALL_PATH (requires sudo)..."
sudo mkdir -p /usr/local/bin
sudo cp "$TEMP_DIR/cupertino" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

# Verify installation
if ! command -v cupertino &> /dev/null; then
    warn "/usr/local/bin may not be in your PATH"
    warn "Add this to your shell profile: export PATH=\"/usr/local/bin:\$PATH\""
fi

VERSION=$(cupertino --version 2>/dev/null || "$INSTALL_PATH" --version)
success "Installed: cupertino $VERSION"

# Download databases
echo ""
info "Downloading documentation databases (~230 MB)..."
cupertino setup

# Done!
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Installation Complete!            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Start the MCP server:"
echo "     ${BLUE}cupertino serve${NC}"
echo ""
echo "  2. Configure Claude Desktop:"
echo "     Edit ~/Library/Application Support/Claude/claude_desktop_config.json"
echo ""
echo '     {
       "mcpServers": {
         "cupertino": {
           "command": "/usr/local/bin/cupertino"
         }
       }
     }'
echo ""
echo "  3. Or add to Claude Code:"
echo "     ${BLUE}claude mcp add cupertino -- /usr/local/bin/cupertino${NC}"
echo ""
echo "Documentation: https://github.com/mihaelamj/cupertino"
echo ""

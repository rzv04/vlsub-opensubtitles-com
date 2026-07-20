#!/bin/bash
set -e

echo "================================================"
echo "VLSub OpenSubtitles.com Extension Installer"
echo "================================================"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if curl is available
if ! command -v curl &> /dev/null; then
    printf "${RED}Error: curl is required but not installed.${NC}\n"
    echo "Please install curl and try again."
    echo ""
    echo "Install curl:"
    echo "  macOS: brew install curl (or use built-in)"
    echo "  Ubuntu/Debian: sudo apt install curl"
    echo "  Fedora: sudo dnf install curl"
    echo "  Arch: sudo pacman -S curl"
    exit 1
fi

# Detect platform and set installation directory
detect_platform() {
    case "$OSTYPE" in
        darwin*)
            PLATFORM="macOS"
            VLC_EXT_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
            ;;
        linux-gnu*|linux-musl*)
            PLATFORM="Linux"
            VLC_EXT_DIR="$HOME/.local/share/vlc/lua/extensions"
            ;;
        msys|cygwin|win*)
            PLATFORM="Windows"
            if [ -n "$APPDATA" ]; then
                VLC_EXT_DIR="$APPDATA/vlc/lua/extensions"
            else
                printf "${RED}Error: Cannot detect VLC extensions directory on Windows.${NC}\n"
                echo "Please install manually by copying vlsubcom.lua to:"
                echo "%APPDATA%\\vlc\\lua\\extensions\\"
                exit 1
            fi
            ;;
        *)
            printf "${RED}Error: Unsupported platform: $OSTYPE${NC}\n"
            echo "Supported platforms: macOS, Linux, Windows (Git Bash/WSL)"
            echo ""
            echo "For manual installation, copy vlsubcom.lua to your VLC extensions directory:"
            echo "  Windows: %APPDATA%\\vlc\\lua\\extensions\\"
            echo "  macOS: ~/Library/Application Support/org.videolan.vlc/lua/extensions/"
            echo "  Linux: ~/.local/share/vlc/lua/extensions/"
            exit 1
            ;;
    esac
}

# Check for unzip (required for SubSource extraction on Linux/macOS)
check_unzip() {
    if [ "$PLATFORM" = "Windows" ]; then
        return
    fi
    
    echo "Checking for unzip utility..."
    if command -v unzip &> /dev/null; then
        printf "${GREEN}✓ unzip found${NC}\n"
    else
        printf "${YELLOW}⚠ unzip not found.${NC}\n"
        if [ "$PLATFORM" = "Linux" ]; then
            echo "Attempting to install unzip..."
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y unzip
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y unzip
            elif command -v pacman &> /dev/null; then
                sudo pacman -S --noconfirm unzip
            else
                echo "Please install 'unzip' manually using your package manager."
                exit 1
            fi
            
            if command -v unzip &> /dev/null; then
                printf "${GREEN}✓ unzip installed successfully${NC}\n"
            else
                printf "${RED}✗ Failed to install unzip. Please install it manually.${NC}\n"
                exit 1
            fi
        else
            echo "Please install 'unzip' manually."
            exit 1
        fi
    fi
}

# Check AI Transcription dependencies (ffmpeg, yt-dlp)
check_ai_deps() {
    echo "Checking AI Transcription dependencies..."
    
    # ffmpeg
    if command -v ffmpeg &> /dev/null; then
        printf "${GREEN}✓ ffmpeg found: $(command -v ffmpeg)${NC}\n"
    else
        printf "${YELLOW}⚠ ffmpeg not found on PATH${NC}\n"
        printf "  ffmpeg will be auto-downloaded on first AI transcription use (Windows only).\n"
        printf "  Or install manually:\n"
        case "$PLATFORM" in
            "macOS")
                printf "  ${BLUE}brew install ffmpeg${NC}\n"
                ;;
            "Linux")
                printf "  ${BLUE}Ubuntu/Debian: sudo apt install ffmpeg${NC}\n"
                printf "  ${BLUE}Fedora: sudo dnf install ffmpeg${NC}\n"
                printf "  ${BLUE}Arch: sudo pacman -S ffmpeg${NC}\n"
                ;;
        esac
    fi
    
    # ffprobe (bundled with ffmpeg)
    if command -v ffprobe &> /dev/null; then
        printf "${GREEN}✓ ffprobe found: $(command -v ffprobe)${NC}\n"
    elif ! command -v ffmpeg &> /dev/null; then
        printf "${YELLOW}⚠ ffprobe not found (will be available when ffmpeg is installed)${NC}\n"
    fi
    
    # yt-dlp (optional, for YouTube URL support)
    if command -v yt-dlp &> /dev/null; then
        printf "${GREEN}✓ yt-dlp found: $(command -v yt-dlp)${NC}\n"
    else
        printf "${YELLOW}⚠ yt-dlp not found (optional - needed for YouTube AI transcription)${NC}\n"
        case "$PLATFORM" in
            "macOS")
                printf "  ${BLUE}Install: brew install yt-dlp  OR  pip install yt-dlp${NC}\n"
                ;;
            "Linux")
                printf "  ${BLUE}Install: pip install yt-dlp  OR  sudo apt install yt-dlp${NC}\n"
                ;;
        esac
    fi
}

# Check if VLC is installed
check_vlc() {
    echo "Checking for VLC installation..."
    
    case "$PLATFORM" in
        "macOS")
            if [ -d "/Applications/VLC.app" ] || command -v vlc &> /dev/null; then
                printf "${GREEN}✓ VLC found${NC}\n"
            else
                printf "${YELLOW}⚠ VLC not found.${NC}\n"
                echo "Download VLC: https://www.videolan.org/vlc/download-macosx.html"
                read -p "Continue installation anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            ;;
        "Linux")
            if command -v vlc &> /dev/null; then
                printf "${GREEN}✓ VLC found${NC}\n"
            else
                printf "${YELLOW}⚠ VLC not found.${NC}\n"
                echo "Install VLC:"
                echo "  Ubuntu/Debian: sudo apt install vlc"
                echo "  Fedora: sudo dnf install vlc"
                echo "  Arch: sudo pacman -S vlc"
                echo "  Or download from: https://www.videolan.org/"
                read -p "Continue installation anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            ;;
        "Windows")
            echo "Please ensure VLC is installed from https://www.videolan.org/"
            ;;
    esac
}

# Create installation directory
create_directory() {
    echo "Creating extension directory..."
    printf "${BLUE}Directory: $VLC_EXT_DIR${NC}\n"
    
    if [ ! -d "$VLC_EXT_DIR" ]; then
        mkdir -p "$VLC_EXT_DIR"
        printf "${GREEN}✓ Directory created${NC}\n"
    else
        printf "${GREEN}✓ Directory exists${NC}\n"
    fi
}

# Backup existing installation
backup_existing() {
    local existing_file="$VLC_EXT_DIR/vlsubcom.lua"
    
    if [ -f "$existing_file" ]; then
        echo "Found existing VLSub installation..."
        local backup_file="$existing_file.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$existing_file" "$backup_file"
        printf "${GREEN}✓ Backup created: $(basename "$backup_file")${NC}\n"
    fi
}

# Download and install the extension
install_extension() {
    local temp_file=$(mktemp)
    local download_url="https://github.com/opensubtitles/vlsub-opensubtitles-com/releases/latest/download/vlsubcom.lua"
    
    echo "Downloading VLSub extension..."
    printf "${BLUE}From: $download_url${NC}\n"
    
    if curl -L -f -o "$temp_file" "$download_url" --progress-bar; then
        printf "${GREEN}✓ Download successful${NC}\n"
    else
        printf "${RED}✗ Download failed${NC}\n"
        echo "Please check your internet connection and try again."
        echo "Or download manually from: https://github.com/opensubtitles/vlsub-opensubtitles-com/releases"
        rm -f "$temp_file"
        exit 1
    fi
    
    echo "Installing extension..."
    mv "$temp_file" "$VLC_EXT_DIR/vlsubcom.lua"
    printf "${GREEN}✓ Installation complete${NC}\n"
    printf "${BLUE}📍 Installed to: $VLC_EXT_DIR/vlsubcom.lua${NC}\n"
}

# Set permissions (Linux/macOS)
set_permissions() {
    if [ "$PLATFORM" != "Windows" ]; then
        chmod 644 "$VLC_EXT_DIR/vlsubcom.lua"
        printf "${GREEN}✓ Permissions set${NC}\n"
    fi
}

# Show completion message
show_completion() {
    echo
    echo "================================================"
    printf "${GREEN}🎉 Installation Complete!${NC}\n"
    echo "================================================"
    echo
    printf "${BLUE}📁 Extension installed to:${NC}\n"
    printf "${YELLOW}   $VLC_EXT_DIR/vlsubcom.lua${NC}\n"
    echo
    printf "${YELLOW}Next steps:${NC}\n"
    printf "1. ${BLUE}Restart VLC Media Player${NC}\n"
    printf "2. ${BLUE}Go to View → VLSub OpenSubtitles.com${NC}\n"
    printf "3. ${BLUE}Enter your OpenSubtitles.com credentials${NC}\n"
    printf "   ${GREEN}(Create free account at https://www.opensubtitles.com/)${NC}\n"
    echo
    printf "${YELLOW}Quick start:${NC}\n"
    printf "• ${BLUE}Hash search:${NC} For exact subtitle matches\n"
    printf "• ${BLUE}Name search:${NC} For flexible title-based search\n"
    printf "• ${BLUE}Double-click subtitle${NC} to download and load\n"
    printf "• ${BLUE}AI Transcription:${NC} Live speech-to-text (local, network, live streams)\n"
    echo
    printf "${YELLOW}AI Transcription Dependencies:${NC}\n"
    printf "• ${BLUE}ffmpeg:${NC} Required - install via package manager or https://ffmpeg.org/\n"
    printf "• ${BLUE}yt-dlp:${NC} Optional - for YouTube URL transcription (pip install yt-dlp)\n"
    echo
    printf "${YELLOW}Support & Documentation:${NC}\n"
    printf "• ${BLUE}Issues:${NC} https://github.com/opensubtitles/vlsub-opensubtitles-com/issues\n"
    printf "• ${BLUE}Docs:${NC} https://github.com/opensubtitles/vlsub-opensubtitles-com\n"
    printf "• ${BLUE}OpenSubtitles:${NC} https://www.opensubtitles.com/\n"
    echo
    printf "${BLUE}💡 To uninstall:${NC} Delete the file at the path shown above\n"
    echo
}

# Main installation process
main() {
    printf "${BLUE}Platform detection...${NC}\n"
    detect_platform
    printf "${GREEN}Platform: $PLATFORM${NC}\n"
    echo
    
    check_vlc
    echo
    
    check_unzip
    echo
    
    check_ai_deps
    echo
    
    create_directory
    echo
    
    backup_existing
    echo
    
    install_extension
    echo
    
    set_permissions
    echo
    
    show_completion
}

# Run installation
main "$@"
#!/bin/bash

set -e

readonly INSTALL_DIR="/opt/Cursor"
readonly DESKTOP_FILE="/usr/share/applications/cursor.desktop"
readonly TEMP_DIR=$(mktemp -d)
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly INSTALL_DIR_BACKUP="${INSTALL_DIR}.backup.${TIMESTAMP}"
readonly DESKTOP_FILE_BACKUP="${DESKTOP_FILE}.backup.${TIMESTAMP}"

# Cleanup function for trap
cleanup_temp() {
    if [ "$?" -ne 0 ]; then
        printf "Restore backup files...\n"
        if [ -d "$INSTALL_DIR_BACKUP" ]; then
            printf " - %s\n" "$INSTALL_DIR"
            sudo rm -rf "$INSTALL_DIR" 2>/dev/null || true
            sudo mv "$INSTALL_DIR_BACKUP" "$INSTALL_DIR"
        fi

        if [ -f "$DESKTOP_FILE_BACKUP" ]; then
            printf " - %s\n" "$DESKTOP_FILE"
            sudo rm -f "$DESKTOP_FILE" 2>/dev/null || true
            sudo mv "$DESKTOP_FILE_BACKUP" "$DESKTOP_FILE"
        fi
    else
        if [ -d "$INSTALL_DIR_BACKUP" ] || [ -f "$DESKTOP_FILE_BACKUP" ]; then
            printf "Delete backup files? (y/N): "
            read -r response
            case "$response" in
            [yY] | [yY][eE][sS])
                printf "Remove backup files\n"
                if [ -d "$INSTALL_DIR_BACKUP" ]; then
                    printf " - %s\n" "$INSTALL_DIR_BACKUP"
                    sudo rm -rf "$INSTALL_DIR_BACKUP"
                fi
                if [ -f "$DESKTOP_FILE_BACKUP" ]; then
                    printf " - %s\n" "$DESKTOP_FILE_BACKUP"
                    sudo rm -f "$DESKTOP_FILE_BACKUP"
                fi
                ;;
            *)
                printf "Keep backup files\n"
                if [ -d "$INSTALL_DIR_BACKUP" ]; then
                    printf " - %s\n" "$INSTALL_DIR_BACKUP"
                fi
                if [ -f "$DESKTOP_FILE_BACKUP" ]; then
                    printf " - %s\n" "$DESKTOP_FILE_BACKUP"
                fi
                ;;
            esac
        fi
    fi

    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        printf "Cleanup: %s\n" "$TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup_temp EXIT

# Check for apt, platform, sudo, curl
if ! command -v apt >/dev/null 2>&1; then
    printf "This script requires apt package manager\n"
    exit 1
fi

arch=$(uname -m)

case "$arch" in
x86_64 | amd64)
    platform="linux-x64"
    ;;
aarch64 | arm64)
    platform="linux-arm64"
    ;;
*)
    printf "Unsupported architecture: %s\n" "$arch"
    exit 1
    ;;
esac

if ! sudo -n true 2>/dev/null; then
    sudo -v
fi

if ! command -v curl >/dev/null 2>&1; then
    sudo apt update && sudo apt install -y curl >/dev/null 2>&1
fi

# Backup existing files
printf "Backup existing files\n"

if [ -d "$INSTALL_DIR" ]; then
    printf " - %s\n" "$INSTALL_DIR"
    sudo mv "$INSTALL_DIR" "$INSTALL_DIR_BACKUP"
fi

if [ -f "$DESKTOP_FILE" ]; then
    printf " - %s\n" "$DESKTOP_FILE"
    sudo mv "$DESKTOP_FILE" "$DESKTOP_FILE_BACKUP"
fi

# Get download URL
printf "Check latest version\n"

api_url="https://cursor.com/api/download?platform=${platform}&releaseTrack=stable"

response=$(curl -fsSL "$api_url")
download_url=$(printf "%s" "$response" | sed -n 's/.*"downloadUrl":"\([^"]*\)".*/\1/p')

if [ -z "$download_url" ]; then
    printf "Failed to extract download URL\n"
    exit 1
fi

if ! printf "%s" "$download_url" | grep -q "\.AppImage$"; then
    printf "Download URL is not an AppImage file\n"
    exit 1
fi

# Download and extract AppImage
printf "Download and extract AppImage\n"

filename=$(basename "$download_url")
appimage_file="$TEMP_DIR/$filename"

if ! sudo curl -fSL --progress-bar -o "$appimage_file" "$download_url"; then
    printf "Download failed\n"
    exit 1
fi

if [ ! -f "$appimage_file" ] || [ ! -s "$appimage_file" ]; then
    printf "Downloaded file is missing or empty\n"
    exit 1
fi

sudo chmod +x "$appimage_file"

cd "$TEMP_DIR"

if ! sudo "$appimage_file" --appimage-extract >/dev/null 2>&1; then
    printf "Failed to extract AppImage\n"
    exit 1
fi

if [ ! -d "$TEMP_DIR/squashfs-root" ]; then
    printf "Extraction directory not found\n"
    exit 1
fi

sudo mv squashfs-root "$INSTALL_DIR"
sudo rm "$appimage_file"

# Setup desktop integration
printf "Setup desktop integration\n"

chrome_sandbox=$(find "$INSTALL_DIR" -name "chrome-sandbox" -type f 2>/dev/null | head -1)
if [ -n "$chrome_sandbox" ]; then
    sudo chown root:root "$chrome_sandbox"
    sudo chmod 4755 "$chrome_sandbox"
fi

source_desktop="$INSTALL_DIR/cursor.desktop"

if [ -f "$source_desktop" ]; then
    sudo cp "$source_desktop" "$DESKTOP_FILE"

    sudo sed -i "s|Exec=cursor|Exec=$INSTALL_DIR/AppRun|g" "$DESKTOP_FILE"
    sudo sed -i "s|^Icon=\(.*\)|Icon=${INSTALL_DIR}/\1.png|" "$DESKTOP_FILE"

    sudo chmod 644 "$DESKTOP_FILE"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications/ 2>/dev/null || true
fi

printf "Installed successfully!\n"
exit 0

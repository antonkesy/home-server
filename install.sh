#!/usr/bin/env bash
set -e

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Generate hardware configuration if it doesn't exist
if [ ! -f hardware-configuration.nix ]; then
    echo "Generating hardware configuration..."
    sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
    echo "Hardware configuration generated"
else
    echo "Hardware configuration exists"
fi

# Create required directories
echo "Creating directories..."
sudo mkdir -p /mnt/music /mnt/movies /mnt/books
sudo mkdir -p /var/lib/nextcloud /var/lib/kavita
echo "Directories created"

# Generate Nextcloud admin password
if [ ! -f /var/lib/nextcloud/admin-pass ]; then
    echo "Generating Nextcloud admin password..."
    tr -dc A-Za-z0-9 </dev/urandom | head -c 32 | sudo tee /var/lib/nextcloud/admin-pass > /dev/null
    sudo chmod 600 /var/lib/nextcloud/admin-pass
    echo "Password saved to /var/lib/nextcloud/admin-pass"
else
    echo "Nextcloud password exists"
fi

# Create SMB credentials file if it doesn't exist
if [ ! -f /etc/smb-credentials ]; then
    echo "Creating SMB credentials template..."
    if [ -f scripts/mount/smb-credentials ]; then
        sudo cp scripts/mount/smb-credentials /etc/smb-credentials
    else
        echo "username=your_nas_username" | sudo tee /etc/smb-credentials > /dev/null
        echo "password=your_nas_password" | sudo tee -a /etc/smb-credentials > /dev/null
    fi
    sudo chmod 600 /etc/smb-credentials
    echo "Edit /etc/smb-credentials with your NAS credentials (or skip if no NAS)"
fi

# Apply NixOS configuration
echo ""
# Try to apply now (switch), fall back to non-flake if needed
if sudo nixos-rebuild switch --flake "$SCRIPT_DIR#home-server" 2>/dev/null; then
    echo "Configuration applied to current system."
else
    echo "nixos-rebuild switch with flakes failed; trying without flakes..."
    sudo nixos-rebuild switch || true
fi

# Ensure this configuration is the default for the next boot
echo "Setting this configuration as the default for the next boot..."
if sudo nixos-rebuild boot --flake "$SCRIPT_DIR#home-server" 2>/dev/null; then
    echo "Configuration scheduled for next boot."
else
    echo "nixos-rebuild boot with flakes failed; trying without flakes..."
    sudo nixos-rebuild boot || true
fi

# If this script is being run from a live installer and /mnt is mounted,
# show how to install the config to the target disk.
if mountpoint -q /mnt; then
    echo ""
    echo "Detected /mnt mountpoint. To install this config to disk, run:"
    echo "  sudo nixos-install --root /mnt --flake "$SCRIPT_DIR#home-server""
fi

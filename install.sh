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

# Generate Nextcloud admin password
if [ ! -f /var/lib/nextcloud/admin-pass ]; then
    echo "Generating Nextcloud admin password..."
    tr -dc A-Za-z0-9 </dev/urandom | head -c 32 | sudo tee /var/lib/nextcloud/admin-pass > /dev/null
    sudo chmod 600 /var/lib/nextcloud/admin-pass
    echo "Password saved to /var/lib/nextcloud/admin-pass"
else
    echo "Nextcloud password exists"
fi

# Apply NixOS configuration
echo ""
# Try to apply now (switch), fall back to non-flake if needed
sudo nixos-rebuild switch --flake "$SCRIPT_DIR#home-server"
echo "Configuration applied to current system."

# Set password for user ak
echo "Setting password for user 'ak'..."
sudo passwd ak

# Ensure this configuration is the default for the next boot
echo "Setting this configuration as the default for the next boot..."
sudo nixos-rebuild boot --flake "$SCRIPT_DIR#home-server"
echo "Configuration scheduled for next boot."

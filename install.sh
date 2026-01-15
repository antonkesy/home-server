#!/usr/bin/env bash
set -e

echo "🚀 Home Server Installation"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "❌ Please run without sudo. Script will request sudo when needed."
    exit 1
fi

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Generate hardware configuration if it doesn't exist
if [ ! -f hardware-configuration.nix ]; then
    echo "📝 Generating hardware configuration..."
    sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
    echo "✅ Hardware configuration generated"
else
    echo "✅ Hardware configuration exists"
fi

# Create required directories
echo "📁 Creating directories..."
sudo mkdir -p /mnt/music /mnt/movies /mnt/books
sudo mkdir -p /var/lib/nextcloud /var/lib/kavita
echo "✅ Directories created"

# Generate Nextcloud admin password
if [ ! -f /var/lib/nextcloud/admin-pass ]; then
    echo "🔑 Generating Nextcloud admin password..."
    tr -dc A-Za-z0-9 </dev/urandom | head -c 32 | sudo tee /var/lib/nextcloud/admin-pass > /dev/null
    sudo chmod 600 /var/lib/nextcloud/admin-pass
    echo "✅ Password saved to /var/lib/nextcloud/admin-pass"
else
    echo "✅ Nextcloud password exists"
fi

# Create SMB credentials file if it doesn't exist
if [ ! -f /etc/smb-credentials ]; then
    echo "🔐 Creating SMB credentials template..."
    if [ -f scripts/mount/smb-credentials ]; then
        sudo cp scripts/mount/smb-credentials /etc/smb-credentials
    else
        echo "username=your_nas_username" | sudo tee /etc/smb-credentials > /dev/null
        echo "password=your_nas_password" | sudo tee -a /etc/smb-credentials > /dev/null
    fi
    sudo chmod 600 /etc/smb-credentials
    echo "⚠️  Edit /etc/smb-credentials with your NAS credentials (or skip if no NAS)"
fi

# Apply NixOS configuration
echo ""
echo "🔧 Applying NixOS configuration..."
sudo nixos-rebuild switch --flake "$SCRIPT_DIR#home-server" || sudo nixos-rebuild switch

echo ""
echo "✅ Installation complete!"
echo ""
echo "🌐 Services will be available at:"
echo "   - Home Assistant: http://lab:8123"
echo "   - Jellyfin:       http://lab:8096"
echo "   - Kavita:         http://lab:5000"
echo "   - Nextcloud:      http://lab:8080"
echo "   - Blocky DNS:     http://lab:4000"
echo ""
echo "💡 Check status: sudo systemctl status home-assistant jellyfin nextcloud-setup kavita blocky"

# NixOS Installation Guide for Home Server

This guide will help you set up your home server using NixOS with all the services (Home Assistant, Jellyfin, Kavita, Nextcloud, and Pi-hole) running in Docker containers.

## Prerequisites

- A machine with NixOS installed (or ready to install NixOS)
- At least 4GB of RAM (8GB+ recommended)
- At least 50GB of free disk space
- Internet connection

## Step 1: Install NixOS (if not already installed)

If you don't have NixOS installed yet:

1. Download the NixOS ISO from https://nixos.org/download.html
2. Create a bootable USB drive
3. Boot from the USB drive
4. Follow the installation instructions: https://nixos.org/manual/nixos/stable/#sec-installation

## Step 2: Clone the Repository

```bash
# Clone this repository to your NixOS system
sudo mkdir -p /home-server
cd /home-server
git clone <your-repo-url> .
```

Alternatively, copy all files from this project to `/home-server/` on your NixOS system.

## Step 3: Generate Hardware Configuration

Generate the hardware configuration for your specific machine:

```bash
# Generate hardware configuration
sudo nixos-generate-config --show-hardware-config > /home-server/hardware-configuration.nix
```

## Step 4: Update Configuration

Edit [configuration.nix](configuration.nix) to include the hardware configuration:

```bash
sudo nano /home-server/configuration.nix
```

Add this line at the top of the file in the imports section:

```nix
imports = [
  ./hardware-configuration.nix
];
```

The configuration should look like:

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ... rest of configuration
}
```

## Step 5: Set Up Media Directories

Create the media directories that will be used by Jellyfin and Kavita:

```bash
sudo mkdir -p /mnt/music
sudo mkdir -p /mnt/movies
sudo mkdir -p /mnt/books
sudo chmod 755 /mnt/{music,movies,books}
```

If you have an NAS or external storage, you can mount it here. See [scripts/mount-nas.sh](scripts/mount-nas.sh) for examples.

## Step 6: Build and Apply the Configuration

### Using Flakes (Recommended)

```bash
# Build the configuration
sudo nixos-rebuild switch --flake /home-server#home-server

# Or if you're already in the /home-server directory:
cd /home-server
sudo nixos-rebuild switch --flake .#home-server
```

### Using Traditional Configuration

```bash
# Link the configuration
sudo ln -sf /home-server/configuration.nix /etc/nixos/configuration.nix

# Build and switch
sudo nixos-rebuild switch
```

## Step 7: Start Docker Services

After the system rebuilds, the systemd services will automatically start the Docker containers. You can check their status:

```bash
# Check all services
sudo systemctl status home-assistant-docker
sudo systemctl status jellyfin-docker
sudo systemctl status kavita-docker
sudo systemctl status nextcloud-docker
sudo systemctl status pihole-docker

# Check Docker containers
sudo docker ps
```

## Step 8: Verify Installation

Run the validation container to check if everything is installed correctly:

```bash
cd /home-server
sudo docker-compose -f docker-compose.validate.yml up
```

This will test connectivity to all services and report their status.

## Step 9: Access Your Services

Once everything is running, you can access your services at:

- **Home Assistant**: http://localhost:8123/
- **Jellyfin**: http://localhost:8096/
- **Kavita**: http://localhost:5000/home
- **Nextcloud**: http://localhost:8080/
- **Pi-hole**: http://localhost:8181/

Replace `localhost` with your server's IP address if accessing from another machine.

## Troubleshooting

### Services not starting

Check the journal logs:
```bash
sudo journalctl -u home-assistant-docker -f
sudo journalctl -u jellyfin-docker -f
# etc...
```

### Docker issues

Restart Docker service:
```bash
sudo systemctl restart docker
```

### Port conflicts

Check if ports are already in use:
```bash
sudo ss -tulpn | grep LISTEN
```

### Firewall issues

Check firewall status:
```bash
sudo iptables -L -n
```

## Updating the System

To update your NixOS system and rebuild:

```bash
# Update flake inputs
sudo nix flake update /home-server

# Rebuild
sudo nixos-rebuild switch --flake /home-server#home-server
```

## Managing Services

```bash
# Stop a service
sudo systemctl stop jellyfin-docker

# Start a service
sudo systemctl start jellyfin-docker

# Restart a service
sudo systemctl restart jellyfin-docker

# Disable a service from starting at boot
sudo systemctl disable jellyfin-docker

# Enable a service to start at boot
sudo systemctl enable jellyfin-docker
```

## Maintenance

### Update Docker Images

```bash
# Pull latest images
cd /home-server/jellyfin
sudo docker-compose pull
sudo docker-compose up -d

# Repeat for other services
```

### Clean Up Docker

```bash
# Remove unused containers, networks, images
sudo docker system prune -a
```

### Backup Configuration

Important directories to backup:
- `/home-server/` - NixOS configuration
- `/home-server/*/config/` - Service configurations
- `/mnt/music`, `/mnt/movies`, `/mnt/books` - Media files

## Additional Configuration

### Setting up SSH

```bash
# Enable SSH in configuration.nix
# Add to configuration.nix:
services.openssh = {
  enable = true;
  settings.PermitRootLogin = "no";
  settings.PasswordAuthentication = false;
};

# Rebuild
sudo nixos-rebuild switch --flake /home-server#home-server
```

### Setting up Automatic Updates

You can enable automatic system updates by adding to [configuration.nix](configuration.nix):

```nix
system.autoUpgrade = {
  enable = true;
  flake = "/home-server#home-server";
  dates = "weekly";
  allowReboot = false;
};
```

## Support

For issues specific to:
- **NixOS**: https://discourse.nixos.org/
- **Home Assistant**: https://community.home-assistant.io/
- **Jellyfin**: https://forum.jellyfin.org/
- **Kavita**: https://discord.gg/kavita
- **Nextcloud**: https://help.nextcloud.com/
- **Pi-hole**: https://discourse.pi-hole.net/

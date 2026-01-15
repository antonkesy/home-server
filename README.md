# Home Server - NixOS Configuration

A comprehensive home server setup for NixOS with Docker-based services including Home Assistant, Jellyfin, Kavita, Nextcloud, and Pi-hole.

## 🚀 Quick Start

### Demo the Configuration (No NixOS Required!)

Test the NixOS configuration in a Docker container without installing NixOS:

```bash
# Build and run the demo validation
make demo

# Or run interactively to explore the configuration
make demo-interactive
```

This will validate:
- Flake configuration syntax
- NixOS configuration validity
- Docker Compose file syntax
- Required directory structure
- Available tools and packages

### For NixOS Users

See [NIXOS_INSTALL.md](NIXOS_INSTALL.md) for complete installation instructions.

```bash
# Clone the repository
sudo mkdir -p /home-server
cd /home-server
git clone <your-repo-url> .

# Generate hardware configuration
sudo nixos-generate-config --show-hardware-config > /home-server/hardware-configuration.nix

# Build and apply configuration
sudo nixos-rebuild switch --flake /home-server#home-server

# Validate installation
sudo docker-compose -f docker-compose.validate.yml up
```

### For Docker/Traditional Setup

If you're not using NixOS, you can still use the Docker Compose files directly:

```bash
make start
```

## 📂 Media Directories

- Music: `/mnt/music`
- Movies: `/mnt/movies`
- Books: `/mnt/books`

## 🌐 Service Addresses

- [Home Assistant](http://localhost:8123/): `http://localhost:8123/`
- [Jellyfin](http://localhost:8096/): `http://localhost:8096/`
- [Kavita](http://localhost:5000/home): `http://localhost:5000/home`
- [Nextcloud](http://localhost:8080/): `http://localhost:8080/`
- [Pi-hole](http://localhost:8181/): `http://localhost:8181/`

## 📋 Features

### NixOS Configuration
- **Declarative Setup**: Entire system configuration in Nix files
- **Reproducible**: Same configuration works across machines
- **Atomic Upgrades**: Rollback if something goes wrong
- **Systemd Integration**: All services managed by systemd

### Services Included
- **Home Assistant**: Home automation platform
- **Jellyfin**: Media server for movies and music
- **Kavita**: Digital library for books and comics
- **Nextcloud**: Self-hosted cloud storage
- **Pi-hole**: Network-wide ad blocker and DNS server

## 🛠️ Installation

### NixOS Installation

1. **Prerequisites**
   - NixOS installed on your system
   - At least 4GB RAM (8GB+ recommended)
   - 50GB+ free disk space
   - Internet connection

2. **Follow the guide**: [NIXOS_INSTALL.md](NIXOS_INSTALL.md)

3. **Validate**: Run the validation container
   ```bash
   sudo docker-compose -f docker-compose.validate.yml up
   ```

### Traditional Docker Setup

```bash
# Setup and start all services
make setup
make start

# Stop all services
make stop
```

## 🧪 Demo Mode

Test the NixOS configuration without a full NixOS installation:

```bash
# Run validation demo
make demo

# Interactive demo mode
make demo-interactive

# Clean up demo container
make demo-clean
```

The demo mode:
- Validates flake configuration
- Checks NixOS syntax
- Verifies Docker Compose files
- Confirms directory structure
- Tests tool availability

This is perfect for:
- Testing configuration changes before deployment
- CI/CD validation
- Learning NixOS configuration
- Previewing the setup

## 📖 Documentation

- [NixOS Installation Guide](NIXOS_INSTALL.md) - Complete guide for NixOS setup
- [Configuration File](configuration.nix) - Main NixOS configuration
- [Flake Configuration](flake.nix) - Nix flake setup
- [Validation Container](docker-compose.validate.yml) - Test all services

## 🔧 Management

### NixOS Commands

```bash
# Rebuild system
sudo nixos-rebuild switch --flake /home-server#home-server

# Check service status
sudo systemctl status jellyfin-docker
sudo systemctl status home-assistant-docker

# View logs
sudo journalctl -u jellyfin-docker -f

# Restart a service
sudo systemctl restart jellyfin-docker
```

### Docker Commands

```bash
# View running containers
sudo docker ps

# View logs
sudo docker logs jellyfin -f

# Restart a container
sudo docker restart jellyfin
```

## 🧪 Testing

Run the validation container to check if all services are running correctly:

```bash
sudo docker-compose -f docker-compose.validate.yml up
```

This will test:
- HTTP connectivity to all services
- Pi-hole DNS functionality
- Service availability on correct ports

## 🔍 Troubleshooting

### Services not starting

```bash
# Check systemd service logs
sudo journalctl -u <service-name>-docker -f

# Check Docker container logs
sudo docker logs <container-name> -f
```

### Port conflicts

```bash
# Check what's using a port
sudo ss -tulpn | grep <port>
```

### Firewall issues

```bash
# Check firewall rules
sudo iptables -L -n

# Reload firewall
sudo systemctl restart firewall
```

## 🔄 Updates

### Update NixOS Configuration

```bash
# Update flake inputs
sudo nix flake update /home-server

# Rebuild with new configuration
sudo nixos-rebuild switch --flake /home-server#home-server
```

### Update Docker Images

```bash
# Navigate to service directory
cd /home-server/jellyfin

# Pull latest image and restart
sudo docker-compose pull
sudo docker-compose up -d
```

## 📊 System Requirements

- **CPU**: 2+ cores recommended
- **RAM**: 8GB minimum, 16GB recommended
- **Storage**: 50GB+ for system, additional for media
- **Network**: Gigabit ethernet recommended

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This project configuration is provided as-is for personal use.

## 🔗 Service Documentation

- [Home Assistant Docs](https://www.home-assistant.io/docs/)
- [Jellyfin Docs](https://jellyfin.org/docs/)
- [Kavita Wiki](https://wiki.kavitareader.com/)
- [Nextcloud Docs](https://docs.nextcloud.com/)
- [Pi-hole Docs](https://docs.pi-hole.net/)

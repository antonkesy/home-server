# Home Server - NixOS Configuration

Home server with Home Assistant, Jellyfin, Kavita, Nextcloud, and Blocky DNS.

## Install

```bash
git clone <repo-url> && cd home-server
./install.sh
```

## Update

```bash
./update.sh
```

## Services

- Home Assistant: `http://lab:8123`
- Jellyfin: `http://lab:8096`
- Kavita: `http://lab:5000`
- Nextcloud: `http://lab:8080`
- Blocky DNS: `http://lab:4000`

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

## Modules

```
modules/
  hardware/r8125.nix    # Network driver
  networking.nix        # Hostname & firewall
  packages.nix          # System packages
  ssh.nix               # SSH server
  bluetooth.nix         # Bluetooth
  nas-mounts.nix        # NAS mounts
  home-assistant.nix    # Home automation
  jellyfin.nix          # Media server
  nextcloud.nix         # Cloud storage
  kavita.nix            # Book reader
  blocky.nix            # DNS & ad-blocking
  users.nix             # User accounts
```

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

install:
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="{{justfile_directory()}}"
    cd "$SCRIPT_DIR"

    if [ ! -f hardware-configuration.nix ]; then
      echo "Generating hardware configuration..."
      sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
      echo "Hardware configuration generated"
    else
      echo "Hardware configuration exists"
    fi

    if [ ! -f /var/lib/nextcloud/admin-pass ]; then
      echo "Generating Nextcloud admin password..."
      tr -dc A-Za-z0-9 </dev/urandom | head -c 32 | sudo tee /var/lib/nextcloud/admin-pass > /dev/null
      sudo chmod 600 /var/lib/nextcloud/admin-pass
      echo "Password saved to /var/lib/nextcloud/admin-pass"
    else
      echo "Nextcloud password exists"
    fi

    echo ""
    sudo nixos-rebuild switch --flake "$SCRIPT_DIR#home-server"
    echo "Configuration applied to current system."

    echo "Setting password for user 'ak'..."
    sudo passwd ak

    echo "Setting this configuration as the default for the next boot..."
    sudo nixos-rebuild boot --flake "$SCRIPT_DIR#home-server"
    echo "Configuration scheduled for next boot."

update:
    sudo nixos-rebuild switch --flake "{{justfile_directory()}}#home-server"

status:
    sudo systemctl status home-assistant.service jellyfin.service nextcloud-setup.service podman-pihole.service --no-pager || true

clean:
    sudo nix-collect-garbage -d

# If PiHole is broken and system needs internet until reboot
tmp-dns:
    sudo bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'

set-pihole-pw:
    sudo podman exec -it pihole pihole setpassword toor
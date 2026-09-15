set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

flake := justfile_directory() + "#lab"

_default:
    @just --list

# First-time setup: hardware config, service secrets, first switch, user password.
install:
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="{{ justfile_directory() }}"
    cd "$SCRIPT_DIR"

    # 32 chars of randomness. Written without an early-exiting pipe stage,
    # because `head -c` upstream of a pipe makes `pipefail` trip on SIGPIPE.
    gen_pw() {
      LC_ALL=C head -c 4096 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32
    }

    # Write $1 to file $2, creating the parent directory. `install -m` sets the
    # mode as the file is created, so the secret is never briefly world-readable.
    # No trailing newline: it would otherwise become part of the password.
    put_secret() {
      sudo install -d -m 0755 "$(dirname "$2")"
      printf '%s' "$1" | sudo install -m 0600 /dev/stdin "$2"
    }

    if [ ! -f hardware-configuration.nix ]; then
      echo "Generating hardware configuration..."
      sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
    else
      echo "Hardware configuration exists"
    fi

    if [ ! -f /var/lib/nextcloud/admin-pass ]; then
      echo "Generating Nextcloud admin password..."
      put_secret "$(gen_pw)" /var/lib/nextcloud/admin-pass
      echo "  -> /var/lib/nextcloud/admin-pass (user: root)"
    else
      echo "Nextcloud password exists"
    fi

    if [ ! -f /var/lib/paperless/admin-pass ]; then
      echo "Generating Paperless admin password..."
      put_secret "$(gen_pw)" /var/lib/paperless/admin-pass
      echo "  -> /var/lib/paperless/admin-pass (user: admin)"
    else
      echo "Paperless password exists"
    fi

    if [ ! -f /var/lib/pihole/pihole.env ]; then
      echo "Generating Pi-hole web password..."
      put_secret "FTLCONF_webserver_api_password=$(gen_pw)" /var/lib/pihole/pihole.env
      echo "  -> /var/lib/pihole/pihole.env"
    else
      echo "Pi-hole password exists"
    fi

    echo ""
    sudo nixos-rebuild switch --flake "{{ flake }}"
    echo "Configuration applied and set as the default for the next boot."

    echo "Setting password for user 'ak'..."
    sudo passwd ak

# Apply the current configuration.
update:
    sudo nixos-rebuild switch --flake "{{ flake }}"

# Build the system closure without activating it. Safe to run any time.
build:
    sudo nixos-rebuild build --flake "{{ flake }}"

# Stage the configuration for the next boot instead of switching live.
boot:
    sudo nixos-rebuild boot --flake "{{ flake }}"

# Pull new nixpkgs and apply. Run `just rollback` if the result misbehaves.
upgrade:
    nix flake update --flake "{{ justfile_directory() }}"
    sudo nixos-rebuild switch --flake "{{ flake }}"

# Activate the previous generation.
rollback:
    sudo nixos-rebuild switch --rollback

# Evaluate the whole configuration without building it (catches option typos).
check:
    nix eval --raw "{{ justfile_directory() }}#nixosConfigurations.lab.config.system.build.toplevel.drvPath"
    @echo ""

# Format every Nix file in the repo.
fmt:
    nix fmt "{{ justfile_directory() }}"

status:
    sudo systemctl status home-assistant.service jellyfin.service nextcloud-setup.service paperless-web.service podman-pihole.service --no-pager || true

# Follow logs for one unit, e.g. `just logs podman-pihole`.
logs unit:
    sudo journalctl -u "{{ unit }}" -f -n 100

# List system generations, so you know what `rollback` goes back to.
generations:
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

clean:
    sudo nix-collect-garbage -d

# If Pi-hole is broken and the system needs internet until reboot.
tmp-dns:
    sudo bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'

# Rotate the Pi-hole web password and restart the container.
set-pihole-pw:
    #!/usr/bin/env bash
    set -euo pipefail
    PW="$(LC_ALL=C head -c 4096 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32)"
    printf 'FTLCONF_webserver_api_password=%s' "$PW" | sudo tee /var/lib/pihole/pihole.env > /dev/null
    sudo chmod 0600 /var/lib/pihole/pihole.env
    sudo systemctl restart podman-pihole.service
    echo "New Pi-hole password: $PW"

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

flake := justfile_directory() + "#home-server"

_default:
    @just --list

# Hardware config, first switch, user password
install:
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="{{ justfile_directory() }}"
    cd "$SCRIPT_DIR"

    if [ ! -f hardware-configuration.nix ]; then
      echo "Generating hardware configuration..."
      sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
    else
      echo "Hardware configuration exists"
    fi

    echo ""
    sudo nixos-rebuild switch --flake "{{ flake }}"

    echo "Setting password for user 'ak'..."
    sudo passwd ak

# Build and stage for the next boot; nothing changes until a reboot
update:
    sudo nixos-rebuild boot --flake "{{ flake }}"
    @echo "staged for next boot - reboot to apply"

# Build without activating
build:
    sudo nixos-rebuild build --flake "{{ flake }}"

# Bump nixpkgs, then stage for next boot
upgrade:
    nix flake update --flake "{{ justfile_directory() }}"
    sudo nixos-rebuild boot --flake "{{ flake }}"
    @echo "staged for next boot - reboot to apply"

# Activate the previous generation
rollback:
    sudo nixos-rebuild switch --rollback

status:
    sudo systemctl status home-assistant.service jellyfin.service nextcloud-setup.service paperless-web.service podman-pihole.service --no-pager || true

# Follow one unit, e.g. `just logs podman-pihole`
logs unit:
    sudo journalctl -u "{{ unit }}" -f -n 100

clean:
    sudo nix-collect-garbage -d

# Internet until reboot when Pi-hole is broken
tmp-dns:
    sudo bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'

# Rotate the Pi-hole web password
set-pihole-pw:
    #!/usr/bin/env bash
    set -euo pipefail
    PW="$(LC_ALL=C head -c 4096 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32)"
    printf 'FTLCONF_webserver_api_password=%s' "$PW" | sudo install -m 0600 /dev/stdin /var/lib/pihole/pihole.env
    sudo systemctl restart podman-pihole.service
    echo "New Pi-hole password: $PW"

# Enter the NAS SMB user and password once; stored in /var/lib/nas/credentials
nas-credentials:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rp "NAS username: " USER
    read -rsp "NAS password: " PW; echo
    sudo install -d -m 0755 /var/lib/nas
    printf 'username=%s\npassword=%s\n' "$USER" "$PW" | sudo install -m 0600 /dev/stdin /var/lib/nas/credentials
    # drop live mounts so the next access uses the new credentials
    sudo systemctl stop 'mnt-nas-*.mount' || true
    echo "Credentials written; the shares mount on next access"

# Print the generated service passwords
passwords:
    #!/usr/bin/env bash
    set -euo pipefail
    show() { printf '%-12s %-6s %s\n' "$1" "$2" "${3:-<not generated>}"; }
    show SERVICE USER PASSWORD
    show nextcloud root "$(sudo cat /var/lib/nextcloud/admin-pass 2>/dev/null || true)"
    show paperless admin "$(sudo cat /var/lib/paperless/admin-pass 2>/dev/null || true)"
    show pihole - "$(sudo cat /var/lib/pihole/pihole.env 2>/dev/null | cut -d= -f2- || true)"

# Rotate the Nextcloud admin password
set-nextcloud-pw:
    #!/usr/bin/env bash
    set -euo pipefail
    PW="$(LC_ALL=C head -c 4096 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32)"
    sudo -u nextcloud env OC_PASS="$PW" nextcloud-occ user:resetpassword --password-from-env root
    printf '%s' "$PW" | sudo install -m 0600 /dev/stdin /var/lib/nextcloud/admin-pass
    echo "New Nextcloud password: $PW"

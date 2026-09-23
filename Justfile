set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

flake := justfile_directory() + "#home-server"
settings := justfile_directory() + "/settings.nix"

_default:
    @just --list

# Regenerate hardware-configuration.nix for this machine
hardware:
    sudo nixos-generate-config --show-hardware-config > "{{ justfile_directory() }}/hardware-configuration.nix"
    nix fmt "{{ justfile_directory() }}/hardware-configuration.nix"

# First switch, then the user password
install:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"
    [ -f hardware-configuration.nix ] || just hardware
    sudo nixos-rebuild switch --flake "{{ flake }}"
    sudo passwd "$(nix eval --raw --file "{{ settings }}" user)"

# Build and stage for the next boot; nothing changes until a reboot
update:
    sudo nixos-rebuild boot --flake "{{ flake }}"
    @echo "staged for next boot - reboot to apply"

# Build without activating
build:
    sudo nixos-rebuild build --flake "{{ flake }}"

# Bump nixpkgs, then stage for the next boot
upgrade: && update
    nix flake update --flake "{{ justfile_directory() }}"

# Activate the previous generation
rollback:
    sudo nixos-rebuild switch --rollback

# Unit status; an inactive service behind an active .socket is idle, not broken
status:
    sudo systemctl status --no-pager -n 0 gen-secrets.service home-assistant.service jellyfin-proxy.socket jellyfin.service nextcloud-proxy.socket nginx.service nextcloud-setup.service nextcloud-media-watch.service paperless-proxy.socket paperless-nas-dirs.service paperless-web.service paperless-consumer.service podman-pihole.service lab-backup.timer || true

# Snapshot config + secrets; destination defaults to settings.nix
backup dest="":
    sudo lab-backup "{{ dest }}"

# Restore the newest archive (or the given one)
restore archive="":
    sudo lab-restore "{{ archive }}"

# Fresh machine: hardware config, install, NAS login, restore
migrate: hardware install nas-credentials restore

# Free space on /, then the big directories
disk:
    df -h /
    sudo du -shxc /var/lib/nextcloud/data /var/cache/jellyfin /var/lib/jellyfin/metadata /var/lib/paperless /var/lib/hass /var/lib/pihole /var/lib/redis-nextcloud /var/lib/redis-paperless /var/lib/containers/storage 2>/dev/null || true

# Follow one unit, e.g. `just logs podman-pihole`
logs unit:
    sudo journalctl -u "{{ unit }}" -f -n 100

# Copy pre-Paperless documents into consume; safe to re-run
import-legacy subdir=".":
    #!/usr/bin/env bash
    set -euo pipefail
    # plain attrset: readable without evaluating the flake
    cfg=$(nix eval --json --file "{{ settings }}" paperless)
    SRC="$(jq -r .legacyDir <<<"$cfg")/{{ subdir }}"
    DST="$(jq -r .dir <<<"$cfg")/consume"
    # triggers the automount; fails fast while the NAS sleeps
    timeout 15 ls "$SRC" >/dev/null || { echo "$SRC unreachable" >&2; exit 1; }
    # copy, not move: paperless deletes what it consumes
    sudo rsync -a --ignore-existing --info=progress2 "$SRC/" "$DST/"
    echo "copied - follow with: just logs paperless-consumer"

# Index NAS files Nextcloud has not seen (also runs from the watcher)
scan:
    sudo systemctl start --no-block nextcloud-media-scan.service
    sudo journalctl -u nextcloud-media-scan -f -n 50

# Garbage-collect; also drops the rollback generations
clean:
    sudo nix-collect-garbage -d

# Public DNS in /etc/resolv.conf until the next network change
tmp-dns:
    sudo bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'

# 32 random alphanumerics; same pipeline as gen-secrets
_pw:
    @LC_ALL=C head -c 4096 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32

# Rotate the Pi-hole web password
set-pihole-pw:
    #!/usr/bin/env bash
    set -euo pipefail
    PW="$(just --justfile "{{ justfile() }}" _pw)"
    printf 'FTLCONF_webserver_api_password=%s' "$PW" | sudo install -m 0600 /dev/stdin /var/lib/pihole/pihole.env
    sudo systemctl restart podman-pihole.service
    echo "New Pi-hole password: $PW"

# Rotate the Nextcloud admin password
set-nextcloud-pw:
    #!/usr/bin/env bash
    set -euo pipefail
    PW="$(just --justfile "{{ justfile() }}" _pw)"
    sudo -u nextcloud OC_PASS="$PW" nextcloud-occ user:resetpassword --password-from-env root
    printf '%s' "$PW" | sudo install -m 0600 /dev/stdin /var/lib/nextcloud/admin-pass
    echo "New Nextcloud password: $PW"

# Enter the NAS SMB login once
nas-credentials:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rp "NAS username: " NAS_USER
    read -rsp "NAS password: " PW; echo
    sudo install -d -m 0755 /var/lib/nas
    printf 'username=%s\npassword=%s\n' "$NAS_USER" "$PW" | sudo install -m 0600 /dev/stdin /var/lib/nas/credentials
    # remount with the new credentials
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
    show pihole - "$(sudo cut -d= -f2- /var/lib/pihole/pihole.env 2>/dev/null || true)"

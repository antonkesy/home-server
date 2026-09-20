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

# Index NAS files Nextcloud has not seen; also runs on its own from the watcher
scan:
    sudo systemctl start nextcloud-media-scan.service
    sudo journalctl -u nextcloud-media-scan -f -n 50

# One-off backfill of every missing Nextcloud thumbnail (hours; see README)
warm-previews:
    #!/usr/bin/env bash
    set -euo pipefail
    # reads every original over SMB once; the hourly pre-generate timer keeps
    # up from then on. one file per size per image, so ask for the few sizes
    # the web UI actually uses
    sudo -u nextcloud nextcloud-occ config:app:set previewgenerator squareSizes --value="32 256"
    sudo -u nextcloud nextcloud-occ config:app:set previewgenerator widthSizes --value="256 384"
    sudo -u nextcloud nextcloud-occ config:app:set previewgenerator heightSizes --value="256"
    df -h /
    sudo -u nextcloud nextcloud-occ preview:generate-all -vv
    df -h /

# Convert the Nextcloud database from SQLite to PostgreSQL (see README)
to-postgres:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"

    # stage two of the move: postgresql has to be up already, which means
    # usePostgres = false has been built and rebooted at least once

    grep -q 'usePostgres = false;' modules/nextcloud.nix \
      || { echo "usePostgres is already true - nothing left to convert"; exit 1; }
    systemctl is-active --quiet postgresql.service \
      || { echo "postgresql is not running - 'just update', reboot, then retry"; exit 1; }

    echo "== quiescing =="
    # every occ unit is guarded by 'occ status --exit-code', which fails in
    # maintenance mode, so nothing scans or pre-generates behind our back
    sudo -u nextcloud nextcloud-occ maintenance:mode --on
    sudo systemctl stop phpfpm-nextcloud.service nextcloud-media-watch.service

    STAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP="/var/lib/nextcloud-sqlite-$STAMP.tar.gz"
    sudo tar czf "$BACKUP" -C / var/lib/nextcloud/config var/lib/nextcloud/data/nextcloud.db
    echo "backup: $BACKUP"

    echo "== converting (it asks for confirmation) =="
    sudo -u nextcloud nextcloud-occ db:convert-type --all-apps --clear-schema \
      pgsql nextcloud /run/postgresql nextcloud
    sudo -u nextcloud nextcloud-occ db:add-missing-indices
    sudo -u nextcloud nextcloud-occ db:add-missing-columns

    sed -i 's/usePostgres = false;/usePostgres = true;/' modules/nextcloud.nix

    cat <<'MSG'

    Converted. Nothing has switched yet: dbtype is pinned by
    override.config.php from the Nix config, which still says sqlite, and
    php-fpm is deliberately left down so nothing writes to either database.

    Finish it:
        just update && sudo reboot
        sudo -u nextcloud nextcloud-occ maintenance:mode --off

    To back out instead, revert the usePostgres line and reboot; the sqlite
    file is still there and still current.
    MSG

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

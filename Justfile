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

# Unit status
status:
    sudo systemctl status --no-pager -n 0 gen-secrets.service mnt-storage.mount storage-dirs.service home-assistant.service jellyfin.service nginx.service nextcloud-setup.service nextcloud-media-watch.service paperless-storage-dirs.service paperless-web.service paperless-consumer.service immich-server.service immich-setup.service tailscaled.service uptime-kuma.service autokuma.service lab-health.timer podman-pihole.service podman-musicgrabber.service pihole-domains.service lab-backup.timer nextcloud-preview-pregenerate.timer nextcloud-preview-generate.timer || true

# Join the tailnet (opens a login URL); re-run after a restore
tailscale-up:
    sudo tailscale up
    tailscale status

# Snapshot config + secrets; destination defaults to settings.nix
backup dest="":
    sudo lab-backup "{{ dest }}"

# Restore the newest archive (or the given one)
restore archive="":
    sudo lab-restore "{{ archive }}"

# Fresh machine: hardware config, install, restore
migrate: hardware install restore

# Free space on / and the array, then the big directories
disk:
    df -h / /mnt/storage
    sudo du -shxc /var/lib/nextcloud/data /var/lib/immich /var/cache/immich /var/lib/uptime-kuma /var/lib/musicgrabber /var/cache/jellyfin /var/lib/jellyfin/metadata /var/lib/paperless /var/lib/hass /var/lib/pihole /var/lib/redis-nextcloud /var/lib/redis-paperless /var/lib/containers/storage 2>/dev/null || true

# Mirror health and disk power state; "clean" is good, "degraded" needs a disk
storage:
    cat /proc/mdstat
    sudo mdadm --detail /dev/md/storage
    # standby = spun down, active/idle = spinning
    sudo hdparm -C /dev/sda /dev/sdb || true

# Follow one unit, e.g. `just logs podman-pihole`
logs unit:
    sudo journalctl -u "{{ unit }}" -f -n 100

# Force storage-dirs' recursive repair; it normally runs on its own
fix-perms:
    #!/usr/bin/env bash
    set -euo pipefail
    root=$(nix eval --raw --file "{{ settings }}" storage.root)
    # dropping the stamp is what makes the next run walk the whole array
    sudo rm -f "$root/.storage-dirs"
    sudo systemctl restart storage-dirs.service
    sudo journalctl -u storage-dirs -n 20 --no-pager

# Index files Nextcloud has not seen (also runs from the watcher)
scan:
    sudo systemctl start --no-block nextcloud-media-scan.service
    sudo journalctl -u nextcloud-media-scan -f -n 50

# Build missing thumbnails now instead of waiting for the nightly run
warm-previews:
    sudo systemctl start --no-block nextcloud-preview-generate.service
    sudo journalctl -u nextcloud-preview-generate -f -n 50

# Re-assert the Immich external library and scan it for new photos
scan-photos:
    sudo systemctl restart --no-block immich-setup.service
    sudo journalctl -u immich-setup -f -n 50

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

# Re-render the Uptime Kuma monitors and sync them
sync-monitors:
    sudo systemctl restart uptime-kuma-setup.service autokuma.service
    sudo journalctl -u autokuma -f -n 50

# Push the host checks to Uptime Kuma now
health:
    sudo systemctl start lab-health.service
    sudo journalctl -u lab-health -n 20 --no-pager

# Rotate the Uptime Kuma admin password
set-uptime-kuma-pw:
    #!/usr/bin/env bash
    set -euo pipefail
    PW="$(just --justfile "{{ justfile() }}" _pw)"
    sudo uptime-kuma-admin password "$PW"
    printf '%s' "$PW" | sudo install -m 0600 /dev/stdin /var/lib/autokuma/admin-pass
    # autokuma logs in with the file
    sudo systemctl restart uptime-kuma-setup.service autokuma.service
    echo "New Uptime Kuma password: $PW"

# Rotate the Immich admin password
set-immich-pw:
    #!/usr/bin/env bash
    set -euo pipefail
    PW="$(just --justfile "{{ justfile() }}" _pw)"
    s() { nix eval --raw --file "{{ settings }}" "$1"; }
    api="http://localhost:$(s ports.immich)/api"
    email="$(s user)@$(s hostName).$(s lan.domain)"
    old=$(sudo cat /var/lib/immich/admin-pass)
    token=$(curl -fsS -X POST "$api/auth/login" -H 'Content-Type: application/json' \
      --data "$(jq -n --arg e "$email" --arg p "$old" '{email: $e, password: $p}')" | jq -r .accessToken)
    uid=$(curl -fsS -H "Authorization: Bearer $token" "$api/users/me" | jq -r .id)
    curl -fsS -o /dev/null -X PUT "$api/admin/users/$uid" -H "Authorization: Bearer $token" \
      -H 'Content-Type: application/json' --data "$(jq -n --arg p "$PW" '{password: $p}')"
    printf '%s' "$PW" | sudo install -m 0600 /dev/stdin /var/lib/immich/admin-pass
    echo "New Immich password: $PW"

# Print the generated service passwords
passwords:
    #!/usr/bin/env bash
    set -euo pipefail
    show() { printf '%-12s %-6s %s\n' "$1" "$2" "${3:-<not generated>}"; }
    show SERVICE USER PASSWORD
    show nextcloud root "$(sudo cat /var/lib/nextcloud/admin-pass 2>/dev/null || true)"
    show paperless admin "$(sudo cat /var/lib/paperless/admin-pass 2>/dev/null || true)"
    show uptime-kuma "$(nix eval --raw --file "{{ settings }}" user)" "$(sudo cat /var/lib/autokuma/admin-pass 2>/dev/null || true)"
    show immich "$(nix eval --raw --file "{{ settings }}" user)@$(nix eval --raw --file "{{ settings }}" hostName).$(nix eval --raw --file "{{ settings }}" lan.domain)" "$(sudo cat /var/lib/immich/admin-pass 2>/dev/null || true)"
    show pihole - "$(sudo cut -d= -f2- /var/lib/pihole/pihole.env 2>/dev/null || true)"

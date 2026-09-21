# shellcheck shell=bash
# put a lab-backup archive onto a freshly installed machine
set -euo pipefail

src="${1:-${LAB_BACKUP_DIR:?}}"
host="${LAB_HOST:?}"

if [ -d "$src" ]; then
  archive=$(timeout 15 find "$src" -maxdepth 1 -name "$host-*.tar.zst" | sort | tail -n 1)
else
  archive="$src"
fi
[ -n "$archive" ] && [ -f "$archive" ] || { echo "no archive at $src" >&2; exit 1; }

echo "restoring $archive"
tar --zstd -xOf "$archive" manifest
echo

stage=$(mktemp -d /var/tmp/lab-restore.XXXXXX)
trap 'rm -rf "$stage"' EXIT
tar --zstd -xf "$archive" -C "$stage" nextcloud.pgdump

systemctl stop home-assistant.service jellyfin.service \
  paperless-scheduler.service paperless-task-queue.service podman-pihole.service \
  phpfpm-nextcloud.service nextcloud-cron.timer nextcloud-media-watch.service

# a stale wal from the fresh install would be replayed onto the restored db
rm -f /var/lib/paperless/db.sqlite3-{wal,shm,journal} \
  /var/lib/pihole/gravity.db-{wal,shm,journal} \
  /var/lib/jellyfin/data/*.db-{wal,shm,journal}

tar --zstd -xf "$archive" -C / --anchored --exclude=manifest --exclude=nextcloud.pgdump

# nextcloud and jellyfin uids differ between installs
chown -R nextcloud:nextcloud /var/lib/nextcloud/config /var/lib/nextcloud/data
[ -d /var/lib/nextcloud/store-apps ] && chown -R nextcloud:nextcloud /var/lib/nextcloud/store-apps
chown -R hass:hass /var/lib/hass
chown -R jellyfin:jellyfin /var/lib/jellyfin
chown -R paperless:paperless /var/lib/paperless
chown -R 1000:1000 /var/lib/pihole

secrets=(/var/lib/nextcloud/admin-pass /var/lib/paperless/admin-pass /var/lib/pihole/pihole.env)
[ -e /var/lib/nas/credentials ] && secrets+=(/var/lib/nas/credentials)
chown root:root "${secrets[@]}" /etc/ssh/ssh_host_*_key*
chmod 0600 "${secrets[@]}" /etc/ssh/ssh_host_*_key
chmod 0644 /etc/ssh/ssh_host_*_key.pub

pg() { runuser -u postgres -- "$@"; }
pg dropdb -h /run/postgresql --force --if-exists nextcloud
pg createdb -h /run/postgresql -O nextcloud nextcloud
pg pg_restore -h /run/postgresql -d nextcloud --no-owner --role=nextcloud -1 --exit-on-error "$stage/nextcloud.pgdump"

# host keys changed
systemctl restart sshd.service

# config.php exists, so this upgrades instead of installing
systemctl start nextcloud-setup.service
nextcloud-occ maintenance:data-fingerprint
# user files are not in the backup; drop their cache rows
nextcloud-occ files:scan --all

systemctl start phpfpm-nextcloud.service nextcloud-cron.timer \
  nextcloud-external-storage.service nextcloud-media-watch.service \
  home-assistant.service jellyfin.service paperless-scheduler.service podman-pihole.service

echo "restored; check with: just status && just passwords"

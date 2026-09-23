# shellcheck shell=bash
# put a lab-backup archive onto a freshly installed machine
set -euo pipefail

src="${1:-}"
src="${src:-${LAB_BACKUP_DIR:?}}"
host="${LAB_HOST:?}"

if [ -d "$src" ]; then
  archive=$(find "$src" -maxdepth 1 -name "$host-*.tar.zst" | sort | tail -n 1 || true)
else
  archive="$src"
fi
[ -n "$archive" ] && [ -f "$archive" ] || { echo "no archive at $src" >&2; exit 1; }

# lab-backup's lock; its timer is Persistent and may fire on a fresh boot
exec 9>/run/lock/lab-backup.lock
flock -n 9 || { echo "a backup is running" >&2; exit 1; }
systemctl stop lab-backup.timer

stage=$(mktemp -d /var/tmp/lab-restore.XXXXXX)
trap 'rm -rf "$stage"; systemctl start lab-backup.timer' EXIT

echo "restoring $archive"
# both sit at the front of the archive
tar --zstd -xOf "$archive" --occurrence=1 manifest
echo
tar --zstd -xf "$archive" -C "$stage" --occurrence=1 nextcloud.pgdump

systemctl stop home-assistant.service jellyfin.service \
  paperless-scheduler.service paperless-task-queue.service podman-pihole.service \
  nginx.service phpfpm-nextcloud.service nextcloud-cron.timer nextcloud-media-watch.service

# fresh-install WALs would replay over the restored db
rm -f /var/lib/paperless/db.sqlite3-{wal,shm,journal} \
  /var/lib/pihole/gravity.db-{wal,shm,journal} \
  /var/lib/jellyfin/data/*.db-{wal,shm,journal}

tar --zstd -xf "$archive" -C / --anchored --exclude=manifest --exclude=nextcloud.pgdump

# uids differ between installs
chown -R nextcloud:nextcloud /var/lib/nextcloud/config /var/lib/nextcloud/data
[ -d /var/lib/nextcloud/store-apps ] && chown -R nextcloud:nextcloud /var/lib/nextcloud/store-apps
chown -R hass:hass /var/lib/hass
chown -R jellyfin:jellyfin /var/lib/jellyfin
chown -R paperless:paperless /var/lib/paperless
chown -R 1000:1000 /var/lib/pihole

secrets=()
for f in /var/lib/nextcloud/admin-pass /var/lib/paperless/admin-pass /var/lib/pihole/pihole.env; do
  [ -e "$f" ] && secrets+=("$f")
done
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
# user files are not in the backup; drop their cache rows. the array is scanned in the background
nextcloud-occ files:scan --all --home-only

systemctl start nextcloud-cron.timer \
  nextcloud-external-storage.service nextcloud-media-watch.service \
  home-assistant.service podman-pihole.service \
  jellyfin.service paperless-scheduler.service nginx.service phpfpm-nextcloud.service
systemctl start --no-block nextcloud-media-scan.service

echo "restored; check with: just status && just passwords"

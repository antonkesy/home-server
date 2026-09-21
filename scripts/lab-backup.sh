# shellcheck shell=bash
# config + secrets snapshot; user files, media and caches stay out
set -euo pipefail

dest="${1:-${LAB_BACKUP_DIR:?}}"
host="${LAB_HOST:?}"
keep="${LAB_BACKUP_KEEP:?}"
[ "$keep" -ge 1 ] || { echo "keep must be >= 1" >&2; exit 1; }

exec 9>/run/lock/lab-backup.lock
flock -n 9 || { echo "another backup is running" >&2; exit 1; }

# triggers the NAS automount; fails fast instead of hanging while the NAS sleeps
timeout 15 mkdir -p "$dest" || { echo "$dest unreachable" >&2; exit 1; }

stage=$(mktemp -d /var/tmp/lab-backup.XXXXXX)
# sqlite holders, down only for the copy
stopped=(jellyfin.service paperless-scheduler.service paperless-task-queue.service podman-pihole.service)
cleanup() {
  systemctl start "${stopped[@]}" || true
  rm -rf "$stage"
}
trap cleanup EXIT

runuser -u postgres -- pg_dump -h /run/postgresql -Fc nextcloud > "$stage/nextcloud.pgdump"

printf 'host=%s\ndate=%s\nnixos=%s\nstateVersion=%s\nnextcloud=%s\npostgresql=%s\n' \
  "$host" "$(date -Is)" "$(cat /run/current-system/nixos-version)" \
  "${LAB_STATE_VERSION:?}" "${LAB_NEXTCLOUD_VERSION:?}" "${LAB_PG_VERSION:?}" > "$stage/manifest"

systemctl stop "${stopped[@]}"

cd /
shopt -s nullglob
include=()
for p in etc/ssh/ssh_host_*_key etc/ssh/ssh_host_*_key.pub \
  var/lib/nas/credentials \
  var/lib/nextcloud/admin-pass var/lib/nextcloud/config var/lib/nextcloud/store-apps \
  var/lib/nextcloud/data/.ocdata var/lib/nextcloud/data/appdata_* \
  var/lib/paperless/admin-pass var/lib/paperless/db.sqlite3* \
  var/lib/paperless/nixos-paperless-secret-key.env \
  var/lib/paperless/superuser-state var/lib/paperless/src-version \
  var/lib/hass var/lib/jellyfin var/lib/pihole; do
  [ -e "$p" ] && include+=("$p")
done

name="$host-$(date +%Y-%m-%d-%H%M).tar.zst"
rc=0
tar --zstd -cf "$stage/$name" --anchored --wildcards \
  --exclude='var/lib/nextcloud/config/override.config.php' \
  --exclude='var/lib/nextcloud/data/appdata_*/preview' \
  --exclude='var/lib/hass/home-assistant_v2.db*' \
  --exclude='var/lib/hass/home-assistant.log*' \
  --exclude='var/lib/hass/deps' \
  --exclude='var/lib/hass/tts' \
  --exclude='var/lib/hass/backups' \
  --exclude='var/lib/hass/.cache' \
  --exclude='var/lib/hass/configuration.yaml' \
  --exclude='var/lib/jellyfin/metadata' \
  --exclude='var/lib/jellyfin/log' \
  --exclude='var/lib/jellyfin/transcodes' \
  --exclude='var/lib/jellyfin/data/keyframes' \
  --exclude='var/lib/jellyfin/data/subtitles' \
  --exclude='var/lib/jellyfin/data/attachments' \
  --exclude='var/lib/pihole/pihole-FTL.db*' \
  --exclude='var/lib/pihole/macvendor.db' \
  --exclude='var/lib/pihole/gravity_old.db' \
  --exclude='var/lib/pihole/listsCache' \
  -C / "${include[@]}" -C "$stage" manifest nextcloud.pgdump || rc=$?
# 1: a live home assistant file changed mid-read
[ "$rc" -le 1 ] || exit "$rc"

systemctl start "${stopped[@]}"

cp "$stage/$name" "$dest/$name.part"
# soft cifs: a dropped write surfaces here, not at cp
sync -f "$dest"
cmp "$stage/$name" "$dest/$name.part"
mv "$dest/$name.part" "$dest/$name"

find "$dest" -maxdepth 1 -name "$host-*.tar.zst" | sort | head -n -"$keep" | xargs -r rm -v --
echo "wrote $dest/$name ($(du -h "$dest/$name" | cut -f1))"

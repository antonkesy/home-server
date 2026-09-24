# Home Server - NixOS Configuration

[![check](https://github.com/antonkesy/home-server/actions/workflows/check.yml/badge.svg)](https://github.com/antonkesy/home-server/actions/workflows/check.yml)

Home server (`lab`) running Home Assistant, Jellyfin, Nextcloud, Paperless-ngx
and Pi-hole, built from a flake.

## Setup

### Hardware

```mermaid
flowchart LR
  router["Fritz!Box<br>192.168.178.1<br>static lease .29"] --- nic["LAN"]

  subgraph lab["lab - 192.168.178.29"]
    nic

    subgraph nvme["nvme0n1 - 512 GB SSD"]
      p1["p1 - 1 GB vfat<br>/boot"]
      p2["p2 - 476 GB ext4<br>/ and /nix/store"]
    end

    subgraph disks["2 x WD Red WD40EFRX - 4 TB each"]
      sda["sda1 - GPT type FD00"]
      sdb["sdb1 - GPT type FD00"]
    end

    md["/dev/md/storage<br>mdadm RAID1<br>homehost lab"]
    ext4["ext4 label storage<br>/mnt/storage<br>3.6 TB usable"]

    subgraph periph["peripherals"]
      igpu["Intel iGPU<br>QSV transcoding"]
      ble["Bluetooth<br>BLE for Home Assistant"]
      zram["zram 7.6 GB swap<br>no swap partition"]
    end
  end

  sda --> md
  sdb --> md
  md --> ext4
```

The mirror is assembled by homehost and mounted by filesystem label, so no
disk, UUID or `/dev/mdN` is named anywhere in the repo. Building one from
blank disks is the **Storage** note below.

### Software

```mermaid
flowchart TD
  client["LAN client"]

  subgraph fw["open in the firewall"]
    ssh["sshd :22"]
    ph["pi-hole in podman<br>:53 DNS, :4000 UI"]
    has["home-assistant :8123"]
    ncb["nginx :8080<br>phpfpm-nextcloud, imaginary"]
    jfb["jellyfin :8096"]
    plb["paperless :28981<br>scheduler, web, consumer, task-queue"]
  end

  subgraph ssdg["SSD - /var/lib"]
    pg[("postgresql")]
    rd[("redis")]
    st["paperless db + index<br>hass, jellyfin, pi-hole state"]
  end

  subgraph raid["RAID1 - /mnt/storage"]
    med["Movies / Music / Shows"]
    doc["Documents/Paperless<br>consume + media"]
    bak["backups/lab"]
  end

  client --> ssh & ph & has
  client --> ncb & jfb & plb
  ph --> st
  has --> st
  ncb --> pg & rd
  ncb --> med & doc
  jfb --> med
  plb --> doc
  plb --> st
  tb["lab-backup.timer<br>Sun 05:30"] --> bak
```

Everything listens directly; the array is the only thing that idles out, so
the services on the left of it stay up and the disks on the right go to
sleep. Not drawn are the jobs that wake them on a schedule - `mdraid-scrub`
and the Paperless sanity check on the first Saturday, `lab-backup` on Sunday
- nor `nix-gc`, `nix-optimise` and `fstrim`, which only ever touch the SSD.

## Install

```bash
nix-shell -p git just
git clone https://github.com/antonkesy/home-server.git && cd home-server
just install
```

`just install` switches the system and sets the password for user `ak`.
Service passwords are generated on the switch (`gen-secrets`) and kept
across rebuilds. On a new machine run `just hardware` first, or
`just migrate` (hardware, install, restore). The two data disks have to be
built into the mirror once by hand; see **Storage** below.

## Services

| Service        | URL                     | Credentials                                   |
| -------------- | ----------------------- | --------------------------------------------- |
| Home Assistant | `http://lab:8123`       | set up on first visit                         |
| Jellyfin       | `http://lab:8096`       | set up on first visit                         |
| Nextcloud      | `http://lab:8080`       | `/var/lib/nextcloud/admin-pass` (user `root`) |
| Paperless-ngx  | `http://lab:28981`      | `/var/lib/paperless/admin-pass` (user `admin`) |
| Pi-hole        | `http://lab:4000/admin` | `/var/lib/pihole/pihole.env`                  |

`just passwords` prints them. Nextcloud reads its file at first setup only;
rotate with `just set-nextcloud-pw`, Pi-hole with `just set-pihole-pw`.

Everything runs all the time and answers immediately. The power saving sits
one level down instead: the two 4 TB disks park after 30 idle minutes
(`storage.standbyMinutes`), which is worth about 6 W against the ~1 W the
idle services cost. Only the SSD stays awake, and Pi-hole - the one service
that runs constantly - lives entirely on it, so DNS never waits for a disk.

The first read from a sleeping array waits five to ten seconds for spin-up.
What wakes the disks: opening Jellyfin, Nextcloud or Paperless; the Sunday
05:30 backup; the first-Saturday scrub and the Paperless sanity check that
rides along with it; and any `nixos-rebuild switch` that changes `smartd`,
because smartd spins both disks up when it starts. Nothing else should -
`smartd` polls with `-n standby,q` so it skips a parked disk silently, and
Nextcloud's `files_no_background_scan` stops cron from walking the array.

## Day to day

`just --list` shows every recipe. Three things it cannot tell you:
`update` and `upgrade` only stage the next boot, `install` is the one recipe
that switches live, and `clean` drops the generations `rollback` needs.
Garbage collection also runs on its own every Sunday, keeping 30 days.

## Backup & restore

`just backup [dir]` writes one `lab-<date>.tar.zst` to
`/mnt/storage/backups/lab`; `lab-backup.timer` does the same every Sunday
morning and keeps the last eight (`backup` in `settings.nix`). Inside:

- the generated passwords, the SSH host keys
- Nextcloud: `config.php`, installed apps, app data, a Postgres dump
- Paperless: database and secret key (the search index is rebuilt on start)
- Home Assistant: `.storage` (integrations, auth, devices)
- Jellyfin: config, library database, plugins
- Pi-hole: `pihole.toml`, `gravity.db`, `dnsmasq.d`

Not inside: user files, media, Paperless documents, previews, caches, logs,
Home Assistant history. The mirror is what covers those, and it only covers
one disk dying - the archive now sits on the same machine as the state it
backs up, so fire, theft or a dead PSU takes both. `just backup /run/media/...`
onto an external disk now and then is the only thing that does not.
Jellyfin, Paperless and Pi-hole are stopped for the duration of the tar, so
LAN DNS is briefly gone; the copy is compared against the staged archive
after a sync.

`just restore [archive]` takes the newest archive in the backup dir, or a
path. It stops the services, extracts over `/var/lib`, recreates the
Nextcloud database, restarts `sshd` with the old host keys and re-runs
`nextcloud-setup`. Restore onto the same or a newer nixpkgs than the archive
(`manifest` inside says which).

## Notes

- **Site settings** live in `settings.nix`: hostname, addresses, ports,
  storage directories, timezone, git identity. The modules only read them.
- **SSH.** Password authentication stays on until a key is in
  `modules/users.nix`; then set `PasswordAuthentication = false` in
  `modules/ssh.nix`.
- **Pi-hole** is v6: settings use `FTLCONF_<section>_<key>` and are read-only
  in the web UI. Allow/deny entries are listed in `settings.nix`
  (`pihole.domains`) and added on every boot; deleting one there does not
  remove it from Pi-hole. The host itself resolves through public DNS, so a broken
  container cannot lock you out of `just rollback`.
- **LAN names.** Pi-hole serves `lab` and `lab.fritz.box` from the server's
  `/etc/hosts`; everything else under `fritz.box` is forwarded to the router,
  because `fritz.box` is a real public domain.
- **Nextcloud** is trimmed to file sharing: `nextcloud-disable-apps` turns
  the stock dashboard, activity, photos and similar apps off on every boot,
  cron runs every 15 minutes. Upgrade one major version at a time
  (`nextcloud35` only once 34 has migrated, see `nextcloud-occ status`).
- **Storage** (`modules/storage.nix`): two 4 TB disks as one mdadm RAID1
  mirror, ext4, mounted at `/mnt/storage` with the directories listed in
  `storage.dirs`. `just storage` prints the array state; `mdmonitor` logs a
  degraded array through `systemd-cat`, `smartd` warns about a dying disk,
  and `mdraid-scrub` read-checks the mirror on the first Saturday of the
  month (`storage.scrubOnCalendar`), which takes hours at low priority.
  Assembly is by homehost, so there is no `ARRAY` line to keep in sync, and
  the mount is by filesystem label, so the config holds before the array
  exists: `mdadm --create ... --homehost=lab --name=storage` over one
  `FD00` partition per disk, then `mkfs.ext4 -L storage`. The mount is
  `nofail`, and every unit that writes there waits on it with
  `RequiresMountsFor` rather than risk building a tree on the SSD.
  `storage-dirs` re-asserts `ak:lab` and `2775` on every boot, plus a
  default ACL, which is what makes the creating process's umask irrelevant
  and lets `nextcloud`, `paperless`, `jellyfin` and `ak` write each other's
  files. It covers the array root and the listed directories, not their
  contents: a tree copied in as root keeps its `root:root`, and `cp -a` or
  `rsync -a` re-apply the source modes over the inherited ACL. `just
  fix-perms` repairs that once, recursively; `just scan` after it, because
  Nextcloud caches a permission per file.
  A udev rule sets a 30-minute ATA standby timer on whichever devices carry
  the RAID superblock, so no serial is hardcoded and it survives the
  enclosure re-enumerating; a USB bridge that rejects the command is ignored,
  and the enclosure's own idle timer is then what matters. `just storage`
  prints the power state. `storage.dirs` is the only list: Nextcloud mounts
  everything but `backups/` as external storage on boot, and every unit that
  touches the array is ordered after `storage-dirs` - Jellyfin included,
  because a library scan against an unmounted array empties the library.
  Jellyfin's own libraries are still pointed at
  `/mnt/storage/{Movies,Music,Shows}` by hand in its dashboard.
- **Paperless** keeps its documents in `/mnt/storage/Documents/Paperless`
  (`paperless.dir`, `Documents/Paperless` in Nextcloud). Drop a scan into
  `consume/` by any route and inotify picks it up.
  `just import-legacy [subdir]` copies the pre-Paperless documents in;
  unparsable files stay behind in `consume/`.
- **Jellyfin hardware transcoding** (Intel QuickSync) still has to be
  enabled in Dashboard > Playback.
- **Jellyfin's scheduled tasks are the one thing this repo cannot set.** They
  live in the service's own data dir, not in nixpkgs. Leave them running and
  the library scan wakes the array twice a day for nothing, so turn the
  periodic trigger off under Dashboard > Scheduled Tasks and scan by hand
  after adding media. The same dashboard owns the listen port, which is why
  `ports.jellyfin` only describes what is already in `network.xml`.
- **Formatting** is checked in CI (`nix fmt`), `hardware-configuration.nix`
  included.

## Problems & Fixes

- **`ssh lab`: connection refused.** `lab` resolves to loopback. Check
  `dig +short lab @192.168.178.29`; `127.0.0.2` means Pi-hole serves a stale
  `/etc/hosts`: `sudo systemctl restart podman-pihole`.
- **No DNS on the server.** `just tmp-dns` writes a public resolver into
  `/etc/resolv.conf`.
- **The array is degraded.** `just storage` names the missing member.
  Partition the replacement the same way (one GPT partition, type `FD00`),
  then `sudo mdadm /dev/md/storage --add /dev/disk/by-id/<new>-part1` and
  watch the resync in `/proc/mdstat`. The filesystem stays up throughout.
- **No delete or rename in Nextcloud.** A local external storage takes every
  permission from the filesystem, so the action is missing wherever
  `nextcloud` cannot write - usually content copied onto the array as root.
  `sudo -u nextcloud test -w /mnt/storage/Movies/<subdir>` says whether that
  is it; `just fix-perms`, then `just scan`.
- **A rebuild left the machine broken.** Pick the previous generation in the
  systemd-boot menu, or `just rollback`. Ten generations are kept; the kernel
  reboots 30 s after a panic.

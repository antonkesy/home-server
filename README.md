# Home Server - NixOS Configuration

Home server (`lab`) running Home Assistant, Jellyfin, Nextcloud, Paperless-ngx
and Pi-hole, built from a flake.

## Install

```bash
nix-shell -p git just
git clone https://github.com/antonkesy/home-server.git && cd home-server
just install
```

`just install` generates `hardware-configuration.nix`, creates a random
password for each service that needs one, switches the system, and sets the
password for user `ak`. It is safe to re-run: existing secrets are kept.
The NAS login is the one secret that cannot be generated: enter it once with
`just nas-credentials` after the first switch.

## Services

| Service        | URL                          | Credentials                    |
| -------------- | ---------------------------- | ------------------------------ |
| Home Assistant | `http://lab:8123`            | set up on first visit          |
| Jellyfin       | `http://lab:8096`            | set up on first visit          |
| Nextcloud      | `http://lab:8080`            | `/var/lib/nextcloud/admin-pass` (user `root`) |
| Paperless-ngx  | `http://lab:28981`           | `/var/lib/paperless/admin-pass` (user `admin`) |
| Pi-hole        | `http://lab:4000/admin`      | `/var/lib/pihole/pihole.env`   |

Secrets are root-owned `0600` files outside the Nix store and outside git.
Read one with `sudo cat <path>`, or print them all with `just passwords`.

Nextcloud reads its file once, at first setup - editing it later changes
nothing. Rotate with `just set-nextcloud-pw`, which resets the password through
`occ` and rewrites the file so `just passwords` stays true.

## Day to day

```bash
just build        # build the closure without activating it
just update       # apply the current config
just upgrade      # bump nixpkgs, then apply
just rollback     # go back to the previous generation
just status       # systemctl status of the main services
just passwords    # print the generated service passwords
just set-nextcloud-pw     # rotate the Nextcloud admin password
just set-pihole-pw        # rotate the Pi-hole web password
just nas-credentials      # enter the NAS SMB login once
just logs podman-pihole   # follow one unit
just clean        # garbage-collect
```

Garbage collection also runs weekly on its own (`nix.gc`), keeping 30 days of
generations, so the store will not quietly fill the disk.

## Notes

- **Site settings.** Every value specific to this LAN lives in `settings.nix`:
  hostname, the server's and the NAS's address, the Fritz!Box subnet and
  domain, upstream DNS, the NAS shares, every service port, timezone and
  locale. Change them there; the modules only read them.
- **Timezone.** Set in `settings.nix` (`Europe/Berlin`). It feeds log
  timestamps, Paperless document dates and the Pi-hole container clock.
- **SSH.** Password authentication is still on because no key is deployed. Put
  a key in `users.users.ak.openssh.authorizedKeys.keys` (`modules/users.nix`),
  confirm you can log in with it, then set `PasswordAuthentication = false` in
  `modules/ssh.nix`.
- **Pi-hole.** The container is v6, which removed the v5 environment variables
  (`WEBPASSWORD`, `PIHOLE_DNS_`, `DNSMASQ_LISTENING`, ...) entirely rather than
  deprecating them. Settings use the `FTLCONF_<section>_<key>` form; anything
  passed as an environment variable becomes read-only in the web UI.
- **LAN names.** `/etc/hosts` (`modules/networking.nix`) maps `lab` and
  `lab.fritz.box` to the server's address; podman copies that file into the
  Pi-hole container, so FTL answers those names for the whole network. Change
  `lan.address` in `settings.nix` if the DHCP lease ever changes. Everything else under
  `fritz.box`, and reverse lookups for `192.168.178.0/24`, is conditionally
  forwarded to the Fritz!Box - `fritz.box` is a real public domain, so without
  that those queries go to the internet and come back NXDOMAIN.
- **The host does not resolve through Pi-hole.** `networking.nameservers`
  points at public DNS on purpose, so that a broken container cannot stop you
  from SSHing in and running `just rollback`.
- **Nextcloud upgrades** only go one major version at a time. Bump
  `services.nextcloud.package` to `nextcloud33` only once 32 has finished
  migrating (`nextcloud-occ status`).
- **NAS media** (`modules/nas.nix`). The MyCloud at `nas.address` shares
  the names listed in `nas.shares` over SMB (both in `settings.nix`), all
  mounted read-write under `/mnt/nas/<name>`. Point a Jellyfin library at the media ones
  (Dashboard > Libraries > Add Media Library). The mounts are automounts:
  nothing happens at boot, the share is mounted on first access and dropped
  again after 10 minutes idle, so a sleeping or switched-off NAS cannot stall
  a rebuild. `soft` means a read fails instead of hanging if the NAS
  disappears mid-playback; swap it for `hard` if playback errors turn out to
  be more annoying than a hung process.

  The login lives in `/var/lib/nas/credentials`, written by
  `just nas-credentials`; until it has been run, accessing a share fails and
  nothing else is affected. SMB has no per-user ownership, so everything shows
  up as `ak:lab` with `0664`/`0775`: `jellyfin` can read, `ak` can write. The
  NAS account itself needs write access on the shares for `rw` to mean
  anything - and note `soft` can lose a write on timeout in a way it cannot
  lose a read.
- **Jellyfin hardware transcoding** is wired up (Intel QuickSync) but still has
  to be enabled in Dashboard > Playback > Hardware acceleration.
- **Formatting** is checked in CI. `hardware-configuration.nix` is committed and
  formatted along with everything else, so run `nix fmt .` if you ever regenerate
  it with `nixos-generate-config`.

## Problems & Fixes

### `ssh lab`: Connection refused

`lab` is resolving to a loopback address. Check what Pi-hole answers:

```bash
dig +short lab @192.168.178.29   # expected: 192.168.178.29
```

`127.0.0.2` means the container is still serving a stale `/etc/hosts` - restart
it with `sudo systemctl restart podman-pihole`. If the client is not using
Pi-hole at all, point its resolver at `192.168.178.29`.

### No DNS on the server

Pi-hole owns port 53. If the container is wedged, `just tmp-dns` writes a
public resolver into `/etc/resolv.conf` until the next reboot.

### A rebuild left the machine broken

Pick the previous generation from the systemd-boot menu, or `just rollback`
once you are back in. Ten generations are kept, and the kernel is set to
reboot 30s after a panic rather than hang.

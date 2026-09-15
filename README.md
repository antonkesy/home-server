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

## Services

| Service        | URL                          | Credentials                    |
| -------------- | ---------------------------- | ------------------------------ |
| Home Assistant | `http://lab:8123`            | set up on first visit          |
| Jellyfin       | `http://lab:8096`            | set up on first visit          |
| Nextcloud      | `http://lab:8080`            | `/var/lib/nextcloud/admin-pass` (user `root`) |
| Paperless-ngx  | `http://lab:28981`           | `/var/lib/paperless/admin-pass` (user `admin`) |
| Pi-hole        | `http://lab:4000/admin`      | `/var/lib/pihole/pihole.env`   |

Secrets are root-owned `0600` files outside the Nix store and outside git.
Read one with `sudo cat <path>`.

## Day to day

```bash
just check        # evaluate the config without building - run before committing
just build        # build the closure without activating it
just update       # apply the current config
just upgrade      # bump nixpkgs, then apply
just rollback     # go back to the previous generation
just generations  # what rollback would go back to
just status       # systemctl status of the main services
just logs podman-pihole   # follow one unit
just clean        # garbage-collect
```

Garbage collection also runs weekly on its own (`nix.gc`), keeping 30 days of
generations, so the store will not quietly fill the disk.

## Notes

- **Timezone.** Set in `configuration.nix` (`Europe/Berlin`). It feeds log
  timestamps, Paperless document dates and the Pi-hole container clock.
- **SSH.** Password authentication is still on because no key is deployed. Put
  a key in `users.users.ak.openssh.authorizedKeys.keys` (`modules/users.nix`),
  confirm you can log in with it, then set `PasswordAuthentication = false` in
  `modules/ssh.nix`.
- **Pi-hole.** The container is v6, which removed the v5 environment variables
  (`WEBPASSWORD`, `PIHOLE_DNS_`, `DNSMASQ_LISTENING`, ...) entirely rather than
  deprecating them. Settings use the `FTLCONF_<section>_<key>` form; anything
  passed as an environment variable becomes read-only in the web UI.
- **The host does not resolve through Pi-hole.** `networking.nameservers`
  points at public DNS on purpose, so that a broken container cannot stop you
  from SSHing in and running `just rollback`.
- **Nextcloud upgrades** only go one major version at a time. Bump
  `services.nextcloud.package` to `nextcloud33` only once 32 has finished
  migrating (`nextcloud-occ status`).
- **Jellyfin hardware transcoding** is wired up (Intel QuickSync) but still has
  to be enabled in Dashboard > Playback > Hardware acceleration.
- **Formatting** is checked in CI. `hardware-configuration.nix` is committed and
  formatted along with everything else, so run `just fmt` if you ever regenerate
  it with `nixos-generate-config`.

## Problems & Fixes

### `ssh lab`: Connection refused

`lab` is probably resolving to a loopback address. Ensure `<IP> lab` exists in
`/etc/hosts` on the client.

### No DNS on the server

Pi-hole owns port 53. If the container is wedged, `just tmp-dns` writes a
public resolver into `/etc/resolv.conf` until the next reboot.

### A rebuild left the machine broken

Pick the previous generation from the systemd-boot menu, or `just rollback`
once you are back in. Ten generations are kept, and the kernel is set to
reboot 30s after a panic rather than hang.

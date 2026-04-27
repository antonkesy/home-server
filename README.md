# Home Server - NixOS Configuration

Home server with Home Assistant, Jellyfin, Kavita, Nextcloud, and PiHole.

## Install

```bash
nix-shell -p git
git clone https://github.com/antonkesy/home-server.git && cd home-server
./install.sh
```
## Services

- Home Assistant: `http://lab:8123`
- Jellyfin: `http://lab:8096`
- Kavita: `http://lab:5000`
- Nextcloud: `http://lab:8080`
- Pi-hole: `http://lab:4000/admin`
- Paperless-ngx: `http://lab:28981/`

## Problems & Fixes

### ssh lab: Connection refused

`lab` hostname is probably a loopback.
Ensure `<IP> lab` exists in `/etc/hosts`
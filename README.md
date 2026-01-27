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
- Blocky DNS: `http://lab:4000`

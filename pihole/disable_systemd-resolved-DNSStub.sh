#!/bin/bash

set -e

echo "[INFO] Disabling systemd-resolved DNSStubListener..."

# Backup original file
CONFIG_FILE="/etc/systemd/resolved.conf"
BACKUP_FILE="/etc/systemd/resolved.conf.bak"

if [ ! -f "$BACKUP_FILE" ]; then
    sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo "[INFO] Backup created at $BACKUP_FILE"
fi

# Edit or insert DNSStubListener=no
if grep -q "^#*DNSStubListener=" "$CONFIG_FILE"; then
    sudo sed -i 's/^#*DNSStubListener=.*/DNSStubListener=no/' "$CONFIG_FILE"
else
    echo "DNSStubListener=no" | sudo tee -a "$CONFIG_FILE" > /dev/null
fi

# Restart systemd-resolved
echo "[INFO] Restarting systemd-resolved..."
sudo systemctl restart systemd-resolved

# Optional: show status
echo "[INFO] systemd-resolved status:"
sudo systemctl status systemd-resolved --no-pager

echo "[SUCCESS] DNSStubListener disabled. Port 53 should now be free."


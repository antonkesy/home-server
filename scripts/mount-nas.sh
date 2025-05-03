#!/bin/bash

sudo apt update -y
sudo apt install -y cifs-utils

sudo mkdir -p /mnt/music
sudo mkdir -p /mnt/movies
sudo mkdir -p /mnt/books

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo cp "$SCRIPT_DIR"/mount/smb-credentials /etc/smb-credentials
sudo chmod 600 /etc/smb-credentials

sudo tee -a /etc/fstab < "$SCRIPT_DIR"/mount/fstab

# test mount
sudo systemctl daemon-reload
sudo mount -a
ls /mnt/music
ls /mnt/movies
ls /mnt/books

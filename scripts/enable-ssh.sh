#!/bin/bash

sudo apt update -y
sudo apt install -y openssh-server

sudo systemctl start ssh
sudo systemctl enable ssh
sudo systemctl status ssh

ip addr

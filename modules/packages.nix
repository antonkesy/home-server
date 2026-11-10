{ pkgs, ... }:

{
  # NixOS already ships coreutils, curl, nc, ping, ip, ss, host, ps, less,
  # strace and iptables; these fill the rest of the usual toolbox
  environment.systemPackages = with pkgs; [
    just
    jq
    yq-go # YouTube/subscriptions.yaml
    rsync
    neovim
    lazygit
    tmux
    ripgrep
    fd
    tree
    file
    pv
    bc
    unzip
    zip
    p7zip

    # processes
    htop
    psmisc # killall, fuser, pstree
    lsof
    sysstat # iostat, sar
    iotop-c # disk io per process, run as iotop-c

    # disks and hardware
    duf # disk usage
    ncdu
    gptfdisk # sgdisk
    hdparm # disk power state
    smartmontools # smartctl
    nvme-cli
    pciutils # lspci
    usbutils # lsusb
    lshw
    dmidecode
    lm_sensors

    # network
    wget
    dig # DNS routing
    whois
    openssl # s_client for the certificate
    traceroute
    tcpdump
    nmap
    arp-scan
    ipcalc
    iperf3
    ethtool
    iw # wi-fi link, signal, scan
    wavemon
    socat
    iftop # traffic per connection
    nethogs # traffic per process
  ];

  # setcap wrapper, so it runs without sudo
  programs.mtr.enable = true;
}

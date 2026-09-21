# every site-specific value in one place; modules take it as `settings`
{
  hostName = "lab";

  # primary account; owns the NAS mounts
  user = "ak";
  group = "lab";

  timeZone = "Europe/Berlin";
  locale = "en_US.UTF-8";
  phoneRegion = "DE";
  ocrLanguages = "deu+eng";

  lan = {
    # static DHCP lease on the Fritz!Box
    address = "192.168.178.29";
    subnet = "192.168.178.0/24";
    router = "192.168.178.1";
    domain = "fritz.box";
  };

  # public resolvers: Pi-hole upstreams, and the host's own fallback so a dead
  # container still leaves SSH + rollback working
  upstreamDns = [
    "1.1.1.1"
    "1.0.0.1"
  ];

  nas = {
    # static DHCP lease on the Fritz!Box
    address = "192.168.178.26";
    # SMB share names, mounted under mountRoot/<name>
    shares = [
      "Movies"
      "Music"
      "Shows"
      "ak"
    ];
    # paperless consumes and stores documents on this one, so it may not idle
    # out from under a running service; the media shares still do
    keepMounted = [ "ak" ];
    mountRoot = "/mnt/nas";
    # written once by `just nas-credentials`
    credentials = "/var/lib/nas/credentials";
  };

  # scanned documents on the `ak` share; Nextcloud shows the tree as
  # NAS/Documents/Paperless
  paperless = {
    dir = "/mnt/nas/ak/Documents/Paperless";
    # pre-paperless documents, imported once with `just import-legacy`
    legacyDir = "/mnt/nas/ak/Documents/Legacy";
    # cifs reports no remote writes, so the consumer polls instead (seconds)
    pollInterval = 60;
    # a file must be this quiet before it is consumed; the 5s default is too
    # tight for a multi-page scan arriving over SMB
    stabilityDelay = 30;
  };

  # config + secrets snapshot to the NAS; `just backup`, `just restore`
  backup = {
    dir = "/mnt/nas/ak/backups/lab";
    keep = 8;
    # after pi-hole's sunday 03:xx gravity run
    onCalendar = "Sun 05:30";
  };

  # all opened in the firewall; jellyfin's is fixed upstream
  ports = {
    ssh = 22;
    dns = 53;
    pihole = 4000;
    nextcloud = 8080;
    jellyfin = 8096;
    homeAssistant = 8123;
    paperless = 28981;
  };
}

# every site-specific value; modules take it as `settings`
let
  nasRoot = "/mnt/nas";
  # the share paperless, the backups and nextcloud's NAS folder live on
  home = "${nasRoot}/ak";
in
{
  hostName = "lab";

  # primary account; owns the NAS mounts
  user = "ak";
  group = "lab";

  git = {
    name = "Anton Kesy";
    email = "anton@kesy.de";
  };

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

  # pi-hole upstreams; also the host's own resolvers (modules/pihole.nix)
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
    # never idle-unmounted: backup, paperless-nas-dirs and nextcloud write here
    keepMounted = [ "ak" ];
    mountRoot = nasRoot;
    # written once by `just nas-credentials`
    credentials = "/var/lib/nas/credentials";
  };

  # NAS/Documents/Paperless in Nextcloud
  paperless = {
    dir = "${home}/Documents/Paperless";
    # imported once with `just import-legacy`
    legacyDir = "${home}/Documents/Legacy";
    # cifs reports no remote writes: the consumer polls (seconds) while paperless is up
    pollInterval = 60;
    # the 5s default is too tight for a multi-page scan over SMB
    stabilityDelay = 30;
  };

  # `just backup`, `just restore`
  backup = {
    dir = "${home}/backups/lab";
    keep = 8;
    # after pi-hole's sunday 03:xx gravity run and the nix jobs
    onCalendar = "Sun 05:30";
  };

  # pi-hole domain lists, applied on every boot (modules/pihole.nix);
  # an entry removed here stays until deleted in the web UI
  pihole.domains = [
    {
      type = "allow";
      kind = "regex";
      domain = "(\\.|^)video-stats\\.l\\.google\\.com$";
      comment = "ReVanced YT History";
    }
    {
      type = "allow";
      kind = "regex";
      domain = "(\\.|^)s\\.youtube\\.com$";
      comment = "ReVanced YT History";
    }
    {
      type = "deny";
      kind = "regex";
      domain = "(\\.|^)instagram\\.com$";
      comment = "";
    }
  ];

  # all opened in the firewall
  ports = {
    ssh = 22;
    dns = 53;
    pihole = 4000;
    nextcloud = 8080;
    jellyfin = 8090;
    homeAssistant = 8123;
    paperless = 28981;
  };

  # stopped after idleTimeout, started on connect (modules/on-demand.nix);
  # these backend ports stay out of `ports`, so the firewall keeps them closed
  onDemand = {
    idleTimeout = "30min";
    # fixed upstream
    jellyfinPort = 8096;
    paperlessPort = 28982;
    nextcloudPort = 8081;
  };
}

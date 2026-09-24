# every site-specific value; modules take it as `settings`
let
  storageRoot = "/mnt/storage";
in
{
  hostName = "lab";

  # primary account; owns the storage tree
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

  # mdadm RAID1 mirror over the two 4 TB disks, ext4 labelled `storage`
  storage = {
    root = storageRoot;
    # the array is found by filesystem label, not by uuid
    label = "storage";
    # hdparm's 30-minute units: 241 = 30 min. multiples of 30, up to 330
    standbyMinutes = 30;
    # created by modules/storage.nix as user:group, setgid and group-writable;
    # everything but `backups` is also a nextcloud external storage
    dirs = [
      "Movies"
      "Music"
      "Shows"
      "Audiobooks"
      "Soundtracks"
      "eBooks"
      "Documents"
      "ak"
      "backups"
    ];
    # first saturday; a read-check of 3.6 T runs for hours at low priority
    scrubOnCalendar = "Sat *-*-1..7 03:00";
  };

  # Documents/Paperless in Nextcloud
  paperless = {
    dir = "${storageRoot}/Documents/Paperless";
    # imported once with `just import-legacy`
    legacyDir = "${storageRoot}/Documents/Legacy";
  };

  # `just backup`, `just restore`
  backup = {
    dir = "${storageRoot}/backups/lab";
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
    # jellyfin reads its port from its own network.xml; 8096 is that default
    jellyfin = 8096;
    homeAssistant = 8123;
    paperless = 28981;
  };
}

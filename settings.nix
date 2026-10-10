# every site-specific value; modules take it as `settings`
let
  storageRoot = "/mnt/storage";
in
{
  hostName = "lab";

  # primary account; owns the storage tree
  user = "ak";
  group = "lab";
  # the login for the services that want an email (immich, bookorbit)
  adminEmail = "anton@kesy.de";

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

  # modules/proxy.nix: every web ui at https://<subdomain>.<domain>, one
  # wildcard certificate from let's encrypt over hostinger's dns api. the names
  # only resolve on the LAN, through pi-hole; the domain's public records are
  # left alone
  domain = "antonkesy.de";
  # keyed like `ports`; nextcloud has no port, nginx serves it directly, and
  # overview is the start page linking all the others (modules/overview.nix)
  subdomains = {
    overview = "lab";
    homeAssistant = "home";
    jellyfin = "jellyfin";
    audiobookshelf = "audiobooks";
    nextcloud = "cloud";
    paperless = "paperless";
    immich = "photos";
    musicGrabber = "music";
    bookOrbit = "books";
    pihole = "pihole";
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
    # each one is also a nextcloud external storage
    dirs = [
      "Movies"
      "Music"
      "Shows"
      "Audiobooks"
      "Podcasts"
      "YouTube"
      "Soundtracks"
      "Books"
      "Photos"
      "Documents"
      "Archive"
      "Backups"
    ];
    # first saturday; a read-check of 3.6 T runs for hours at low priority
    scrubOnCalendar = "Sat *-*-1..7 03:00";
  };

  # Documents/Paperless in Nextcloud
  paperless = {
    dir = "${storageRoot}/Documents/Paperless";
  };

  # modules/immich.nix
  immich = {
    # the read-only external library; one of storage.dirs
    libraryDir = "Photos";
    # uploads from the app; under the library dir so nextcloud sees them, and
    # excluded from the external library so immich does not import them twice
    uploadDir = "${storageRoot}/Photos/Immich";
    # nightly external-library scan, in the same disk-wake window as
    # nextcloud.previewOnCalendar
    scanCron = "30 2 * * *";
  };

  # modules/nextcloud.nix
  nextcloud = {
    # the storage.dirs whose previews are built ahead of time. pre-generating
    # the whole array once filled the SSD
    previewDirs = [ "Photos" ];
    # a preview run is skipped while / has less free than this, in GB
    previewMinFreeGB = 50;
    # nightly pass over previewDirs, ahead of the 03:15 nix gc
    previewOnCalendar = "02:30";
  };

  # modules/musicgrabber.nix: single-track downloads from the web UI
  musicGrabber = {
    # one of storage.dirs; downloads land in <Artist>/<Album>/ underneath,
    # where jellyfin and nextcloud already look
    dir = "${storageRoot}/Music";
    # pinned; bump by hand. fully qualified: podman has no search registries
    image = "docker.io/g33kphr33k/musicgrabber:4.3.0";
  };

  # modules/bookorbit.nix: the ebook library, read in place
  bookOrbit = {
    # one of storage.dirs; mounted as /books, scanned where it is. uploads
    # from the web UI land in it as ak:lab
    dir = "${storageRoot}/Books";
    # pinned; bump by hand
    image = "ghcr.io/bookorbit/bookorbit:3.2.0";
  };

  # modules/audiobookshelf.nix: audiobooks and podcasts, read in place
  audiobookshelf = {
    # both in storage.dirs; added as libraries by hand in the web UI
    audiobooksDir = "${storageRoot}/Audiobooks";
    podcastsDir = "${storageRoot}/Podcasts";
  };

  # modules/ytdl-sub.nix: youtube channels as jellyfin tv shows
  ytdlSub = {
    # one of storage.dirs; each show is <name>/Season NN/ underneath
    dir = "${storageRoot}/YouTube";
    # a ytdl-sub media quality preset; best is whatever youtube has, 4K
    # included, merged into mp4
    quality = "Best Video Quality";
    # sponsorblock segments marked as chapters in every video, for jellyfin to
    # skip; the video itself stays whole. every category ytdl-sub knows. the
    # chapters are titled "[SponsorBlock]: <name>" (README, ytdl-sub)
    sponsorBlock = [
      "sponsor" # Sponsor
      "selfpromo" # Unpaid/Self Promotion
      "interaction" # Interaction Reminder
      "intro" # Intermission/Intro Animation
      "outro" # Endcards/Credits
      "preview" # Preview/Recap
      "filler" # Filler Tangent
      "music_offtopic" # Non-Music Section
      "poi_highlight" # Highlight, a single point
    ];
    # a video is fetched only once it is this many days old, so the
    # crowd-sourced sponsorblock segments have had time to arrive. 0 is the
    # night after the upload
    delayDays = 3;
    # nightly, in the window nextcloud.previewOnCalendar already wakes the
    # disks for
    onCalendar = "02:30";
    # the shows live in <dir>/subscriptions.yaml, edited in nextcloud and read
    # on every run. this only seeds that file when it does not exist yet.
    # show name -> seasons, as ytdl-sub's TV Show Collection takes them.
    # s01 is usually the channel itself, which catches every upload no
    # playlist below claims; s02 and up are playlists; s00 is specials.
    # the whole history is downloaded on the first run. a /show/VL<id> link
    # from youtube is the playlist <id>
    initialShows = {
      "coldmirror" = {
        s01_name = "Videos";
        s01_url = "https://www.youtube.com/@coldmirror";
        s02_name = "5 Minuten Harry Podcast";
        s02_url = "https://www.youtube.com/playlist?list=PLDvBqWb1UAGeEt9n6vFH_zdGw65Obf3sH";
      };
    };
  };

  # `just backup`, `just restore`
  backup = {
    # lab's own archives, under the user-facing Backups
    dir = "${storageRoot}/Backups/lab";
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

  # all opened in the firewall; the web ones are also behind the proxy
  ports = {
    ssh = 22;
    dns = 53;
    http = 80;
    https = 443;
    pihole = 4000;
    # jellyfin reads its port from its own network.xml; 8096 is that default
    jellyfin = 8096;
    homeAssistant = 8123;
    paperless = 28981;
    immich = 2283;
    musicGrabber = 38274;
    bookOrbit = 3000;
    audiobookshelf = 13378;
  };
}

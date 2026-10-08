{ lib, settings, ... }:

let
  ycfg = settings.ytdlSub;
  unit = "ytdl-sub-youtube";
in
{
  assertions = [
    {
      assertion =
        lib.elem (baseNameOf ycfg.dir) settings.storage.dirs && dirOf ycfg.dir == settings.storage.root;
      message = "settings.ytdlSub.dir must be one of storage.dirs";
    }
  ];

  # no daemon: a oneshot on a timer, the subscriptions straight from settings.nix
  services.ytdl-sub.instances.youtube = {
    enable = true;
    schedule = ycfg.onCalendar;
    readWritePaths = [ ycfg.dir ];

    # upstream: /run/ytdl-sub/youtube, which is RAM. a video is staged whole
    # before it is moved onto the array, so the SSD instead
    config.configuration.working_directory = lib.mkForce "/var/lib/ytdl-sub/youtube/working";

    subscriptions = {
      __preset__.overrides.tv_show_directory = ycfg.dir;
      # one season per url; a video in a playlist and in the channel's uploads
      # lands once, in the higher season. the download archive of each show is
      # a dotfile in its own directory on the array, so /var/lib holds nothing
      "Jellyfin TV Show Collection | ${ycfg.quality}" = lib.mapAttrs' (
        name: lib.nameValuePair "~${name}"
      ) ycfg.shows;
    };
  };

  # the array is group-writable by setgid + default ACL (modules/storage.nix)
  users.users.ytdl-sub.extraGroups = [ settings.group ];

  systemd.services.${unit} = {
    # a run against an unmounted array would download every show again onto
    # the SSD, since the archives that say what is there live on the array
    unitConfig.RequiresMountsFor = [ ycfg.dir ];
    serviceConfig = {
      # what it writes on the array stays writable for ak and nextcloud
      UMask = "0002";
      # upstream sandbox; in a private user namespace `lab` is unmapped
      PrivateUsers = lib.mkForce false;
      # a first run over a whole channel takes hours
      TimeoutStartSec = "infinity";
    };
  };
}

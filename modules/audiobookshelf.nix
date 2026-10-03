{ lib, settings, ... }:

let
  acfg = settings.audiobookshelf;
  dirs = [
    acfg.audiobooksDir
    acfg.podcastsDir
  ];
  inStorage =
    dir: lib.elem (baseNameOf dir) settings.storage.dirs && dirOf dir == settings.storage.root;
in
{
  assertions = [
    {
      assertion = lib.all inStorage dirs;
      message = "settings.audiobookshelf dirs must each be one of storage.dirs";
    }
  ];

  # state (config, database, item metadata) in /var/lib/audiobookshelf; the
  # libraries are added by hand in Settings > Libraries, as with jellyfin
  services.audiobookshelf = {
    enable = true;
    # the module binds to loopback by default
    host = "0.0.0.0";
    # networking.nix opens it; openFirewall stays off
    port = settings.ports.audiobookshelf;
  };

  # the array is group-writable by setgid + default ACL (modules/storage.nix);
  # podcast downloads and "store cover with item" write there
  users.users.audiobookshelf.extraGroups = [ settings.group ];

  systemd.services.audiobookshelf = {
    # a library scan against an unmounted array empties the library
    unitConfig.RequiresMountsFor = dirs;
    # what it writes on the array stays writable for ak and nextcloud
    serviceConfig.UMask = "0002";
  };
}

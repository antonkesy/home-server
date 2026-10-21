{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  cfg = config.services.jellyfin;

  # "HH:MM" as .NET ticks since midnight, 100 ns each
  ticksAt =
    time:
    let
      parts = map lib.toIntBase10 (lib.splitString ":" time);
    in
    (lib.elemAt parts 0 * 60 + lib.elemAt parts 1) * 60 * 10000000;

  # upstream keys a task's triggers by the MD5 of its UTF-16LE type name as a
  # .NET Guid; this one is RefreshMediaLibraryTask ("Scan Media Library")
  libraryScanTask = "7738148f-fcd0-7979-c7ce-b148e06b3aed";

  # its default is every 12 h, counted from startup: a full walk of the array at
  # a different hour after every boot
  libraryScanTriggers = pkgs.writeText "jellyfin-library-scan.js" (
    builtins.toJSON [
      {
        Type = "DailyTrigger";
        TimeOfDayTicks = ticksAt settings.jellyfin.libraryScanAt;
      }
    ]
  );
in
{
  # the port is in settings.ports, which networking.nix opens; jellyfin itself
  # reads it from /var/lib/jellyfin/config/network.xml, not from nix
  services.jellyfin.enable = true;

  # triggers are only read at start; a change in Dashboard > Scheduled Tasks
  # lasts until the next one
  systemd.services.jellyfin = {
    preStart = ''
      install -D -m 600 ${libraryScanTriggers} "${cfg.configDir}/ScheduledTasks/${libraryScanTask}.js"
    '';
    restartTriggers = [ libraryScanTriggers ];
  };

  # client auto-discovery
  networking.firewall.allowedUDPPorts = [
    1900
    7359
  ];

  # QSV; enable in Dashboard > Playback
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  # render/video for QSV; the array is group-writable by setgid + default ACL
  # (modules/storage.nix), and jellyfin saves artwork next to the media
  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    settings.group
  ];
}

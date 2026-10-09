{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  ycfg = settings.ytdlSub;
  instance = config.services.ytdl-sub.instances.youtube;
  yaml = pkgs.formats.yaml { };
  yq = lib.getExe pkgs.yq-go;

  # edited in nextcloud (YouTube is a share); read on every run, no rebuild
  showsFile = "${ycfg.dir}/subscriptions.yaml";
  # the module's RuntimeDirectory
  subscriptions = "/run/ytdl-sub/youtube/subscriptions.yaml";
  # the module's StateDirectory; a secret, so not on the share
  cookies = "/var/lib/ytdl-sub/youtube/cookies.txt";

  # what the file starts as when there is none
  seed =
    pkgs.runCommand "subscriptions.yaml"
      {
        shows = builtins.toJSON ycfg.initialShows;
        passAsFile = [ "shows" ];
      }
      ''
        {
          echo '# one entry per show; each URL is a season. s01 is usually the'
          echo '# channel (every upload), s02 and up playlists, s00 specials. a'
          echo '# video in several lands once, in the highest season. read on'
          echo '# every run (02:30, or `just youtube`)'
          ${yq} -P -o yaml "$showsPath"
        } > $out
      '';

  # applies to every show
  preset = yaml.generate "preset.yaml" {
    overrides = {
      tv_show_directory = ycfg.dir;
      # upstream: "{episode_date_standardized} - {title}". the date is already
      # the episode number (sNN.eYYMMDDNN), which is what keeps the order
      episode_title = "{title}";
    };
    # upstream stops a URL at its first already-archived video, so a channel
    # whose newest videos are in never gets its older ones (a run that failed
    # or was stopped partway). archived ones are skipped by id from the
    # listing, without fetching them, so walking every URL costs little
    ytdl_options = {
      break_on_existing = false;
      # without a signed-in session youtube answers most video requests from
      # a home IP with "Sign in to confirm you're not a bot". put there by
      # `just youtube-cookies`; while it is missing yt-dlp runs without
      cookiefile = cookies;
      # the progress bar is a journal line several times a second
      noprogress = true;
    };
    # chapters only, nothing cut: jellyfin's chapter segments provider turns
    # them into segments a client skips
    chapters = lib.optionalAttrs (ycfg.sponsorBlock != [ ]) {
      sponsorblock_categories = ycfg.sponsorBlock;
    };
    # non-breaking upstream: a newer video is skipped, not archived, and
    # picked up by a later run
    date_range = lib.optionalAttrs (ycfg.delayDays > 0) {
      before = "today-${toString ycfg.delayDays}days";
    };
  };

  # showsFile holds only the shows; preset, quality and directory stay here.
  # the `~` that marks a show as override variables is added if missing
  prepare = pkgs.writeShellScript "ytdl-sub-youtube-prepare" ''
    set -euo pipefail
    [ -e ${showsFile} ] || install -m 0664 ${seed} ${showsFile}
    # ytdl-sub takes any key as a variable, so a typo (s01_names) is
    # silently a season without a name. only warn: other overrides are valid
    ${yq} '(. // {}) | to_entries | .[] | .key as $show | (.value // {}) | keys | .[]
      | select(test("^s[0-9]{2}_(name|url)$") | not) | $show + ": " + .' ${showsFile} \
      | sed 's/^/warning: subscriptions.yaml: not sNN_name or sNN_url: /' >&2
    ${yq} '{
      "__preset__": load("${preset}"),
      "Jellyfin TV Show Collection | ${ycfg.quality}":
        ((. // {}) | with_entries(.key |= sub("^~?", "~")))
    }' ${showsFile} > ${subscriptions}
  '';
in
{
  assertions = [
    {
      assertion =
        lib.elem (baseNameOf ycfg.dir) settings.storage.dirs && dirOf ycfg.dir == settings.storage.root;
      message = "settings.ytdlSub.dir must be one of storage.dirs";
    }
  ];

  # no daemon: a oneshot on a timer
  services.ytdl-sub.instances.youtube = {
    enable = true;
    schedule = ycfg.onCalendar;
    readWritePaths = [ ycfg.dir ];

    # upstream: /run/ytdl-sub/youtube, which is RAM. a video is staged whole
    # before it is moved onto the array, so the SSD instead
    config.configuration.working_directory = lib.mkForce "/var/lib/ytdl-sub/youtube/working";
    # the "see /tmp/ytdl-sub.errors…" file is in the unit's PrivateTmp,
    # gone once the run ends. a failed show's full debug log lands here
    config.configuration.persist_logs = {
      logs_directory = "/var/lib/ytdl-sub/youtube/logs";
      keep_successful_logs = false;
    };
  };

  # the array is group-writable by setgid + default ACL (modules/storage.nix)
  users.users.ytdl-sub.extraGroups = [ settings.group ];

  systemd.services.ytdl-sub-youtube = {
    # a run against an unmounted array would download every show again onto
    # the SSD, since the archives that say what is there live on the array
    unitConfig.RequiresMountsFor = [ ycfg.dir ];
    serviceConfig = {
      ExecStartPre = [ "${prepare}" ];
      # upstream reads a subscriptions file generated from nix
      ExecStart = lib.mkForce "${lib.getExe config.services.ytdl-sub.package} --config ${yaml.generate "config.yaml" instance.config} sub ${subscriptions}";
      # what it writes on the array stays writable for ak and nextcloud
      UMask = "0002";
      # upstream sandbox; in a private user namespace `lab` is unmapped
      PrivateUsers = lib.mkForce false;
      # a first run over a whole channel takes hours
      TimeoutStartSec = "infinity";
    };
  };
}

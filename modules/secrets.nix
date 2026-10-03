{ pkgs, ... }:

let
  users = [
    "nextcloud-setup.service"
    "paperless-scheduler.service"
    "paperless-web.service"
    "paperless-consumer.service"
    "paperless-task-queue.service"
    "podman-pihole.service"
    "podman-bookorbit.service"
    "bookorbit-setup.service"
    "immich-setup.service"
    "uptime-kuma.service"
    "uptime-kuma-setup.service"
    "lab-health.service"
  ];
in
{
  # on switch, not in `just install`: a rebuild must not depend on a recipe
  systemd.services.gen-secrets = {
    wantedBy = [ "multi-user.target" ];
    # requiredBy too: these start before multi-user.target is reached
    requiredBy = users;
    before = users;
    path = with pkgs; [ coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      # fixed-size read: `head -c` upstream of a pipe trips pipefail on SIGPIPE
      pw() {
        LC_ALL=C head -c 4096 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32
      }

      # bookorbit's setup rejects a password without a digit, an upper and a
      # lower case letter; 32 random alphanumerics miss one about 1 in 250
      mixed() {
        local p
        while p=$(pw); ! [[ $p == *[0-9]* && $p == *[a-z]* && $p == *[A-Z]* ]]; do :; done
        printf '%s' "$p"
      }

      ensure() {
        [ -s "$1" ] && return 0
        [ -d "$(dirname "$1")" ] || install -d -m 0755 "$(dirname "$1")"
        printf '%s' "$2" | install -m 0600 /dev/stdin "$1"
        echo "generated $1"
      }

      ensure /var/lib/nextcloud/admin-pass "$(pw)"
      ensure /var/lib/paperless/admin-pass "$(pw)"
      ensure /var/lib/immich/admin-pass "$(pw)"
      ensure /var/lib/autokuma/admin-pass "$(pw)"
      # one token per push monitor (modules/uptime-kuma.nix)
      ensure /var/lib/autokuma/push-tokens "$(printf '%s=%s\n' \
        storage-array "$(pw)" root-disk "$(pw)" backup "$(pw)" tailscale "$(pw)")"
      ensure /var/lib/pihole/pihole.env "FTLCONF_webserver_api_password=$(pw)"
      ensure /var/lib/bookorbit/admin-pass "$(mixed)"
      # the setup token gates the first account (modules/bookorbit.nix)
      ensure /var/lib/bookorbit/bookorbit.env "$(printf '%s=%s\n' \
        JWT_SECRET "$(pw)" PODCAST_ENCRYPTION_KEY "$(pw)" SETUP_BOOTSTRAP_TOKEN "$(pw)")"
    '';
  };
}

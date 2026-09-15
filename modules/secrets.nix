{ config, pkgs, ... }:

{
  # generated on switch, not by `just install`: a rebuild must not depend on
  # having run an imperative recipe first
  systemd.services.gen-secrets = {
    wantedBy = [ "multi-user.target" ];
    before = [
      "nextcloud-setup.service"
      "paperless-scheduler.service"
      "paperless-web.service"
      "paperless-consumer.service"
      "paperless-task-queue.service"
      "podman-pihole.service"
    ];
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

      ensure() {
        [ -s "$1" ] && return 0
        [ -d "$(dirname "$1")" ] || install -d -m 0755 "$(dirname "$1")"
        printf '%s' "$2" | install -m 0600 /dev/stdin "$1"
        echo "generated $1"
      }

      ensure /var/lib/nextcloud/admin-pass "$(pw)"
      ensure /var/lib/paperless/admin-pass "$(pw)"
      ensure /var/lib/pihole/pihole.env "FTLCONF_webserver_api_password=$(pw)"
    '';
  };
}

.PHONY: install update status help

install:
	./install.sh

update:
	@sudo nixos-rebuild switch --flake .#home-server

status:
	@sudo systemctl status home-assistant.service jellyfin.service nextcloud-setup.service kavita.service blocky.service --no-pager || true

clean:
	@sudo nix-collect-garbage -d

# If PiHole is borken and System needs internet until reboot
tmp-dns:
	@sudo bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'

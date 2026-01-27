.PHONY: install update status help

install:
	./install.sh

update:
	sudo nixos-rebuild switch --flake "home-server"
	sudo nixos-rebuild switch

status:
	@sudo systemctl status home-assistant.service jellyfin.service nextcloud-setup.service kavita.service blocky.service --no-pager || true

clean:
	@sudo nix-collect-garbage -d

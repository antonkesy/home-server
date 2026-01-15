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

# Demo validation targets
demo: demo-build demo-run

demo-build:
	@docker build -f Dockerfile.demo -t home-server-nixos-demo .

demo-run:
	@docker run --rm home-server-nixos-demo

demo-interactive:
	@docker run --rm -it home-server-nixos-demo /bin/bash

demo-clean:
	@docker rmi home-server-nixos-demo 2>/dev/null || true

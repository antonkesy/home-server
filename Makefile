.PHONY: setup start stop demo demo-build demo-run demo-clean

all: start

setup:
	sudo systemctl stop apache2
	sudo systemctl disable apache2

start: setup
	${MAKE} -C ./home-assistant
	${MAKE} -C ./jellyfin
	${MAKE} -C ./kavita
	${MAKE} -C ./nextcloud
	${MAKE} -C ./pihole

stop:
	${MAKE} -C ./home-assistant stop
	${MAKE} -C ./jellyfin stop
	${MAKE} -C ./kavita stop
	${MAKE} -C ./nextcloud stop
	${MAKE} -C ./pihole stop

# Demo targets for testing NixOS configuration in Docker
demo: demo-build demo-run

demo-build:
	@echo "Building NixOS demo container..."
	docker build -f Dockerfile.demo -t home-server-nixos-demo .

demo-run:
	@echo "Running NixOS configuration validation..."
	@echo ""
	docker run --rm home-server-nixos-demo

demo-interactive:
	@echo "Starting interactive NixOS demo container..."
	docker run --rm -it home-server-nixos-demo /bin/bash

demo-clean:
	@echo "Cleaning up demo container..."
	docker rmi home-server-nixos-demo || true

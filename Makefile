.PHONY: setup start

all: start

setup:
	sudo systemctl disable apache2

start: setup
	${MAKE} ./home-assistant
	${MAKE} ./jellyfin
	${MAKE} ./kavita
	${MAKE} ./nextcloud

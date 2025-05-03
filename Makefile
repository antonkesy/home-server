.PHONY: setup start

all: start

setup:
	sudo systemctl disable apache2

start: setup
	${MAKE} -C ./home-assistant
	${MAKE} -C ./jellyfin
	${MAKE} -C ./kavita
	${MAKE} -C ./nextcloud

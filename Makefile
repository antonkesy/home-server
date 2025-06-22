.PHONY: setup start

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

.PHONY: setup start stop

all: start

setup:
	docker volume create nextcloud_aio_mastercontainer

start: setup
	docker compose up -d

stop:
	docker compose stop

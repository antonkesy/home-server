.PHONY: setup start

all: start

setup:
	docker volume create nextcloud_aio_mastercontainer

start: setup
	docker compose up -d

.PHONY: setup start stop get-password

all: start

setup:
	./disable_systemd-resolved-DNSStub.sh

start: setup
	docker compose up -d
	make get-password > password.txt

stop:
	docker compose stop

get-password:
	docker logs pihole | grep random

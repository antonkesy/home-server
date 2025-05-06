.PHONY: start stop

all: start

start:
	docker compose up -d

# https://www.hacs.xyz/docs/use/download/download/#to-download-hacs-container
install_hacs: start
	docker exec -it homeassistant bash -c "wget -O - https://get.hacs.xyz | bash -"
	docker compose restart
	echo "https://www.hacs.xyz/docs/use/configuration/basic/#to-set-up-the-hacs-integration"

stop:
	docker compose stop

.PHONY: setup install rebuild start stop status check-secrets create-secrets clean

all: status

# Full installation process
install: check-secrets create-secrets rebuild
	@echo ""
	@echo "✅ Installation complete!"
	@echo ""
	@echo "Service URLs:"
	@echo "  - Home Assistant: http://localhost:8123"
	@echo "  - Jellyfin:       http://localhost:8096"
	@echo "  - Nextcloud:      http://localhost:80"
	@echo "  - Kavita:         http://localhost:5000"
	@echo "  - Blocky DNS:     http://localhost:4000"
	@echo ""
	@echo "SSH server is enabled on port 22"
	@echo "NAS shares will auto-mount when accessed"
	@echo ""
	@echo "Run 'make status' to check service status"
	@echo "Run 'make mount-nas' to manually mount NAS shares"

# Create required secrets and directories
create-secrets:
	@echo "Creating required secrets and directories..."
	@sudo mkdir -p /var/lib/nextcloud
	@if [ ! -f /var/lib/nextcloud/admin-pass ]; then \
		echo "Creating Nextcloud admin password..."; \
		tr -dc A-Za-z0-9 </dev/urandom | head -c 32 | sudo tee /var/lib/nextcloud/admin-pass > /dev/null; \
		sudo chmod 600 /var/lib/nextcloud/admin-pass; \
		echo "Password saved to /var/lib/nextcloud/admin-pass"; \
	else \
		echo "Nextcloud admin password already exists"; \
	fi
	@sudo mkdir -p /mnt/music /mnt/movies /mnt/books
	@sudo mkdir -p /var/lib/kavita
	@if [ ! -f /etc/smb-credentials ]; then \
		echo "Creating SMB credentials file..."; \
		sudo cp scripts/mount/smb-credentials /etc/smb-credentials; \
		sudo chmod 600 /etc/smb-credentials; \
		echo "⚠️  Please edit /etc/smb-credentials with your NAS credentials"; \
	else \
		echo "SMB credentials already exist"; \
	fi
	@echo "✅ Secrets and directories created"

# Check if secrets exist
check-secrets:
	@echo "Checking for required secrets..."
	@if [ -f /var/lib/nextcloud/admin-pass ]; then \
		echo "✅ Nextcloud admin password exists"; \
	else \
		echo "⚠️  Nextcloud admin password will be created"; \
	fi
	@if [ -f /etc/smb-credentials ]; then \
		echo "✅ SMB credentials exist"; \
	else \
		echo "⚠️  SMB credentials will be created"; \
	fi

rebuild:
	@echo "Rebuilding NixOS configuration..."
	sudo nixos-rebuild switch

test:
	@echo "Testing NixOS configuration..."
	sudo nixos-rebuild test

boot:
	@echo "Setting NixOS configuration for next boot..."
	sudo nixos-rebuild boot

# Show service status
status:
	@echo "Service Status:"
	@echo ""
	@echo "Home Assistant:"
	@sudo systemctl status home-assistant.service --no-pager -l || true
	@echo ""
	@echo "Jellyfin:"
	@sudo systemctl status jellyfin.service --no-pager -l || true
	@echo ""
	@echo "Nextcloud:"
	@sudo systemctl status nextcloud-setup.service --no-pager -l || true
	@echo ""
	@echo "Kavita:"
	@sudo systemctl status kavita.service --no-pager -l || true
	@echo ""
	@echo "Blocky DNS:"
	@sudo systemctl status blocky.service --no-pager -l || true

# Start all services
start:
	@sudo systemctl start home-assistant.service || true
	@sudo systemctl start jellyfin.service || true
	@sudo systemctl start nextcloud-setup.service || true
	@sudo systemctl start kavita.service || true
	@sudo systemctl start blocky.service || true

# Stop all services
stop:
	@sudo systemctl stop home-assistant.service || true
	@sudo systemctl stop jellyfin.service || true
	@sudo systemctl stop nextcloud-setup.service || true
	@sudo systemctl stop kavita.service || true
	@sudo systemctl stop blocky.service || true

restart: stop start

mount-nas:
	@sudo systemctl start mnt-music.mount || true
	@sudo systemctl start mnt-movies.mount || true
	@sudo systemctl start mnt-books.mount || true

unmount-nas:
	@sudo systemctl stop mnt-music.mount || true
	@sudo systemctl stop mnt-movies.mount || true
	@sudo systemctl stop mnt-books.mount || true

clean:
	@sudo nix-collect-garbage -d

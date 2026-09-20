# Variables
COMPOSE_FILE = srcs/docker-compose.yml
DATA_DIR = /home/$(USER)/data
SECRETS = db_root_password db_password wp_admin_password wp_user_password

.PHONY: all secrets build up down stop start logs ps clean fclean re

all: build up

# Generate any missing secret with a random password (existing ones are kept)
secrets:
	@mkdir -p secrets
	@for s in $(SECRETS); do \
		[ -f secrets/$$s.txt ] || { openssl rand -base64 18 > secrets/$$s.txt; echo "created secrets/$$s.txt"; }; \
	done

# Create data directories
$(DATA_DIR)/mariadb:
	mkdir -p $(DATA_DIR)/mariadb

$(DATA_DIR)/wordpress:
	mkdir -p $(DATA_DIR)/wordpress

# Build images
build: secrets $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	docker compose -f $(COMPOSE_FILE) build

# Start services
up: $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	docker compose -f $(COMPOSE_FILE) up -d

# Stop and remove containers (data is kept)
down:
	docker compose -f $(COMPOSE_FILE) down

# Stop / start without removing containers
stop:
	docker compose -f $(COMPOSE_FILE) stop

start:
	docker compose -f $(COMPOSE_FILE) start

logs:
	docker compose -f $(COMPOSE_FILE) logs -f

ps:
	docker compose -f $(COMPOSE_FILE) ps

# Remove this project's containers and images only
clean:
	docker compose -f $(COMPOSE_FILE) down --rmi all

# Full clean: also remove this project's volumes and the data on the host
fclean:
	docker compose -f $(COMPOSE_FILE) down --rmi all --volumes
	sudo rm -rf $(DATA_DIR)

# Rebuild everything
re: fclean all

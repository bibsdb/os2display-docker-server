#
# OS2display infrastructure makefile.

MAKEFLAGS += --no-print-directory

# =============================================================================
# MAIN COMMAND TARGETS
# =============================================================================
.DEFAULT_GOAL := help

help: ## Display a list of the public targets
# Find lines that starts with a word-character, contains a colon and then a
# doublehash (underscores are not word-characters, so this excludes private
# targets), then strip the hash and print.
	@grep -E -h "^\w.*:.*##" $(MAKEFILE_LIST) | sed -e 's/\(.*\):.*##\(.*\)/\1	\2/'

install: ## Install the project.
	$(MAKE) _show_preinstall_notes
	$(MAKE) _dc_compile

	@echo "Installing"
	
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml pull
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml up --force-recreate --detach --remove-orphans

	@echo "Waiting for database to be ready"
	sleep 10

	@echo "Initialize the database"
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml exec api bin/console doctrine:schema:create

	@echo "Clearing the cache"
	$(MAKE) cc

	@echo "Create jwt key pair"
	docker compose --env-file .env.local --env-file .env.docker.local  -f docker-compose.yml exec api bin/console lexik:jwt:generate-keypair --skip-if-exists
	
	$(MAKE) tenant_add

	@echo "CREATE AN ADMIN USER. CHOOSE THE TENANT YOU JUST CREATED."
	$(MAKE) user_add
	$(MAKE) _show_notes

reinstall: ## Reinstall from scratch. Removes the database, all containers and volumes.
	$(MAKE) down
	$(MAKE) install

down:  ## Remove all containers and volumes.
	$(MAKE) stop 
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml down -v

up:  ## Take the environment up without altering the existing state of the containers.
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml up -d

up-dev-mode: ## Take the environment up with code checked out and available in bind mount (rw)
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml exec --user root api chown -R 1000:1000 /var/www/html

	


stop: ## Stop all containers without altering anything else.
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml stop

tenant_add: ## Add a new tenant group
	@echo ""
	@echo "Add a tenant"
	@echo "===================================================="
	@echo "A tenant is a group of users that share the same configuration. F. ex. IT, Library, Schools etc."
	@echo "You have to provide tenant id, tenant title and optionally a description."
	@echo "===================================================="
	@echo ""
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml exec -T api bin/console app:tenant:add

user_add: ## Add a new user (editor or admin)
	@touch .env.temp && echo "$(ENV_CONTENTS)" > .env.temp # Recreate .env.temp if it is missing
	@echo ""
	@echo "Add a user"
	@echo "===================================================="
	@echo "You have to provide email, password, full name, role (editor or admin) and the tenant id."
	@echo "===================================================="
	@echo ""
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml exec -T api bin/console app:user:add

logs: ## Follow docker logs from the containers
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml logs -f --tail=50

cc: ## Clear the cache
	docker compose --env-file .env.local --env-file .env.docker.local -f docker-compose.yml exec api bin/console cache:clear

# =============================================================================
# HELPERS
# =============================================================================
# These targets are usually not run manually.


_show_preinstall_notes:
	@echo ""
	@echo "===================================================="
	@echo "Pre-installation Tasks"
	@echo "===================================================="
	@echo "Complete the following pre-install tasks before continuing."
	@echo "===================================================="
	@echo ""
	@echo "- Copy .env.example to .env.docker.local"
	@echo "- In .env.docker.local provide your own configuration settings."
	@echo "- Copy mariadb/.env.database.example to mariadb/.env.database.local."
	@echo "- In mariadb/.env.database.local provide your own configuration settings."
	@echo "- Copy your SSL certificate files (docker.crt and docker.key) to the ssl-folder"
	@echo ""
	@echo "Have you completed the above pre-install tasks? (yes/no)"
	@read answer && case $$answer in [Yy][Ee][Ss]) ;; *) echo "Please complete the pre-install tasks before continuing."; exit 1;; esac


_show_notes:
	@echo ""
	@echo "===================================================="
	@echo "OS2display now is available via the URLs below"
	@echo "===================================================="
	@echo "Admin: https://<your-domain>/admin"
	@echo "Screen: https://<your-domain>/screen"
	@echo "===================================================="
	@echo ""
	
_dc_compile:
	# Compile the Docker Compose configuration from multiple YAML files
	@COMPOSE_FILES="-f docker-compose.server.yml"; \
	if grep -q '^INTERNAL_DATABASE=true' .env.docker.local; then \
		COMPOSE_FILES="$$COMPOSE_FILES -f docker-compose.mariadb.yml"; \
	fi; \
	if grep -q '^INTERNAL_PROXY=true' .env.docker.local; then \
		COMPOSE_FILES="$$COMPOSE_FILES -f docker-compose.traefik.yml"; \
	fi; \
	docker compose --env-file .env.local --env-file .env.docker.local $$COMPOSE_FILES config > docker-compose.yml






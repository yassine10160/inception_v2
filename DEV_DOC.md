# Developer Documentation

How to set up, build, run and debug the Inception stack. For usage as an end user, see [USER_DOC.md](USER_DOC.md).

## 1. Set up from scratch

### Prerequisites

- Linux, Docker Engine and the Compose v2 plugin (`docker compose version`)
- `make`, `openssl`, `sudo` (only for `make fclean`)
- Free port **443** on the host

### Configuration files

| File                    | Purpose                                                                 |
|-------------------------|-------------------------------------------------------------------------|
| `srcs/.env`             | Non-sensitive variables, loaded into every service through `env_file`. **Git-ignored: create it from the template below** |
| `secrets/*.txt`         | Passwords, exposed as Docker secrets (`/run/secrets/<name>`). **Git-ignored** |
| `srcs/docker-compose.yml` | Services, network, volumes, secrets                                   |

#### Create `srcs/.env`

The file is not in the repository. Create `srcs/.env` with this content and replace `<login>` with your 42 login:

```bash
DOMAIN_NAME=<login>.42.fr
MYSQL_DATABASE=wordpress_db
MYSQL_USER=wp_user

# WordPress settings
WORDPRESS_DB_NAME=wordpress_db
WORDPRESS_DB_USER=wp_user
WORDPRESS_DB_HOST=mariadb
WORDPRESS_TABLE_PREFIX=wp_

# The admin username must NOT contain "admin" or "administrator"
WP_ADMIN_USER=<admin_username>
WP_ADMIN_EMAIL=<admin_username>@<login>.42.fr
WP_USER=<username>
WP_USER_EMAIL=<username>@<login>.42.fr
```

Rules to keep in mind:
- Put **no passwords** in this file. They belong in `secrets/`.
- `MYSQL_DATABASE`/`WORDPRESS_DB_NAME` and `MYSQL_USER`/`WORDPRESS_DB_USER` must be identical pairs.
- `WORDPRESS_DB_HOST` must be the MariaDB service name (`mariadb`).
- Write values without quotes, and put comments on their own line (not after a value).
- `DOMAIN_NAME` must match the `/etc/hosts` entry and the URL you open in the browser.

#### `srcs/.env` variables

| Variable                                   | Used by             | Meaning                                    |
|--------------------------------------------|---------------------|--------------------------------------------|
| `DOMAIN_NAME`                              | nginx, wordpress    | Server name, certificate CN, WordPress URL |
| `MYSQL_DATABASE`, `MYSQL_USER`             | mariadb             | Database and user created on first start   |
| `WORDPRESS_DB_NAME/USER/HOST`, `WORDPRESS_TABLE_PREFIX` | wordpress | Written into `wp-config.php`  |
| `WP_ADMIN_USER`, `WP_ADMIN_EMAIL`          | wordpress           | Administrator (must not contain "admin")   |
| `WP_USER`, `WP_USER_EMAIL`                 | wordpress           | Extra user with the `author` role          |

Secrets (one password per file, no other content):

| Secret file                    | Mounted in                  | Used for                       |
|--------------------------------|-----------------------------|--------------------------------|
| `secrets/db_root_password.txt` | mariadb                     | MariaDB `root` password        |
| `secrets/db_password.txt`      | mariadb, wordpress          | Password of `MYSQL_USER`       |
| `secrets/wp_admin_password.txt`| wordpress                   | WordPress administrator        |
| `secrets/wp_user_password.txt` | wordpress                   | WordPress author user          |

`make build` generates any missing secret with `openssl rand`. Existing files are never overwritten. **Never commit `secrets/`.**

Add the domain to your hosts file:

```bash
echo "127.0.0.1 yafahfou.42.fr" | sudo tee -a /etc/hosts
```

## 2. Build and launch

### With the Makefile

```bash
make            # secrets → data dirs → docker compose build → up -d
make down       # remove containers, keep data
make clean      # + remove this project's images
make fclean     # + remove volumes and /home/$USER/data  (destroys data)
make re         # fclean + all
make logs       # follow logs      make ps   # container status
```

The Makefile only touches this project's resources. It never runs a global `docker system prune`.

### With Docker Compose directly

```bash
docker compose -f srcs/docker-compose.yml build [--no-cache] [service]
docker compose -f srcs/docker-compose.yml up -d [service]
docker compose -f srcs/docker-compose.yml down
```

The data directories `/home/$USER/data/{mariadb,wordpress}` must exist before `up` (`make build` / `make up` create them).

## 3. Manage containers and volumes

```bash
docker compose -f srcs/docker-compose.yml ps          # status (also: make ps)
docker logs -f nginx                                  # logs of one service
docker exec -it wordpress bash                        # shell in a container
docker exec -it mariadb mysql -uroot -p               # SQL shell (prompts for db_root_password)
docker exec wordpress wp user list --path=/var/www/html --allow-root
docker volume ls                                      # named volumes
docker volume inspect srcs_wordpress_data             # shows the host path (device)
docker network inspect srcs_inception-network
```

Rebuild one service after changing its Dockerfile, script or config:

```bash
docker compose -f srcs/docker-compose.yml build mariadb
docker compose -f srcs/docker-compose.yml up -d mariadb
```

Handy checks:

```bash
curl -kI https://yafahfou.42.fr                                   # 200 through nginx
echo | openssl s_client -connect yafahfou.42.fr:443 2>/dev/null | grep Protocol   # TLS 1.2/1.3
docker exec mariadb cat /proc/1/comm                              # PID 1 = mysqld (same idea for nginx / php-fpm8.2)
```

## 4. Where the data lives and how it persists

| Volume           | Container path     | Host path                       | Content                      |
|------------------|--------------------|---------------------------------|------------------------------|
| `mariadb_data`   | `/var/lib/mysql`   | `/home/$USER/data/mariadb`      | Database files               |
| `wordpress_data` | `/var/www/html`    | `/home/$USER/data/wordpress`    | WordPress core, themes, uploads, `wp-config.php` (shared by `wordpress` and `nginx`) |

They are **named volumes** using the `local` driver with `type: none, o: bind, device: /home/${USER}/...`, so Docker manages them by name while the data sits at a known host location.

- `make down` / `docker compose down` / reboots: **data kept**.
- `make fclean`: volumes and host directories **deleted**.
- Files created by the containers belong to the container UIDs (`mysql`, `www-data`), so removing the data directories needs `sudo`.

## 5. How each container starts (and why)

Every container runs its main process in the **foreground as PID 1** via `exec`, with no `tail -f` / `sleep infinity` hacks, so Docker sees crashes and `restart: always` works.

- **mariadb**: `tools/init_db.sh`. Reads passwords from `/run/secrets`. Initialises the data directory if needed. If the `MYSQL_DATABASE` directory doesn't exist yet, it starts a temporary server with `--skip-networking`, sets the root password, creates the database and user (`'%'`), and shuts the temporary server down. Then `exec mysqld`. Setup runs only once. Later starts go straight to `mysqld`.
  > Note: the Debian package pre-creates `/var/lib/mysql/mysql` in the image, so "first start" is detected by the absence of the application database, not of the system tables.
- **wordpress**: `tools/setup_wordpress.sh`. Downloads WordPress and writes `wp-config.php` if missing, **waits for MariaDB's TCP port** (only opened after MariaDB's setup finishes), runs `wp core install` + `wp user create` if `wp core is-installed` fails, then `exec php-fpm8.2 -F`. Because install is keyed on the database state rather than on `wp-config.php`, an interrupted first start recovers on the next restart.
- **nginx**: `tools/generate_ssl.sh`. Creates a self-signed certificate (CN = `DOMAIN_NAME`), substitutes `${DOMAIN_NAME}` into `nginx.conf` with `sed` (nginx does not expand environment variables), runs `nginx -t`, then `exec nginx -g "daemon off;"`.

Other config: `mariadb/conf/50-server.cnf` (listens on all interfaces of the private network, logs to stderr so `docker logs` shows errors), `wordpress/conf/www.conf` (PHP-FPM pool listening on `9000`), `nginx/conf/nginx.conf` (TLS 1.2/1.3 only, FastCGI to `wordpress:9000`, security headers).

## 6. Debugging tips

- **Read the logs first**: `make logs`.
- **WordPress can't connect to the DB**: `docker exec wordpress cat /run/secrets/db_password` must match what MariaDB was initialised with. Secrets are applied on **first** initialisation only. If you changed a secret afterwards, run `make re` (or change the password inside MariaDB / WordPress).
- **Changes to a script or Dockerfile have no effect**: rebuild the image (`docker compose ... build <service>`). Scripts are copied at build time. For a fresh WordPress or DB install you must also delete the data (`make fclean`), since setup is skipped once it has run.
- **`permission denied` on `/home/$USER/data`**: files there are owned by container users. Use `sudo`.
- **Port 443 already in use**: stop the other service (`sudo ss -ltnp | grep :443`).
- **Name resolves but connection fails**: check `/etc/hosts`, then `docker compose ps`.

## 7. Pre-push checklist

- [ ] `secrets/` and `srcs/.env` are not tracked: `git check-ignore secrets/db_password.txt srcs/.env` prints both paths, and `git ls-files | grep -iE "secret|\.env"` prints nothing. **Do this before the first commit.**
- [ ] No password anywhere in `srcs/`, the docs or the git history.
- [ ] `make fclean && make` works from a clean state, and https://yafahfou.42.fr loads.
- [ ] `make down && make up` keeps the site content (persistence).
- [ ] `docker exec mariadb mysql -uwp_user -e 'select 1'` is refused (no empty passwords).
- [ ] Only port 443 is published (`docker ps`).
- [ ] Images are built from `debian:bookworm`, none uses the `latest` tag, and image names match service names.
- [ ] README, USER_DOC and DEV_DOC are up to date.

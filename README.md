*This project has been created as part of the 42 curriculum by yafahfou.*

# Inception

## Description

Inception is a system-administration project: a small web infrastructure built with **Docker Compose** inside a Linux host. Three services run in their own containers, each built from a hand-written Dockerfile on `debian:bookworm` (the penultimate stable Debian release):

| Service     | Role                                             | Exposed                 |
|-------------|--------------------------------------------------|-------------------------|
| `nginx`     | Reverse proxy, TLS termination (TLSv1.2 / 1.3)   | **443** (only entry point) |
| `wordpress` | WordPress + PHP-FPM, configured with WP-CLI      | 9000 (internal network) |
| `mariadb`   | Database backend                                 | 3306 (internal network) |

```
 browser ──HTTPS:443──▶ [ nginx ] ──FastCGI:9000──▶ [ wordpress / php-fpm ] ──SQL:3306──▶ [ mariadb ]
                            │                               │                                  │
                            └──────── wordpress_data ───────┘                             mariadb_data
                                   (site files, shared)                                   (database files)
```

Only NGINX is reachable from outside, over HTTPS on port 443. The three containers talk to each other on a private bridge network (`inception-network`). Data survives container removal thanks to two named volumes stored under `/home/<login>/data`. Passwords are provided through Docker secrets, and every container restarts automatically if it crashes.

### Design choices

**Virtual Machines vs Docker.** A VM emulates a whole machine, with its own kernel, and is heavy (gigabytes, minutes to boot) but strongly isolated. A container shares the host kernel and isolates only processes, filesystem and network. It is small, starts in seconds and is easy to reproduce from a Dockerfile. Here, containers let us run three isolated services with one command and no hypervisor overhead, at the cost of weaker isolation than a VM.

**Secrets vs Environment Variables.** Environment variables are visible through `docker inspect`, inherited by child processes and easily leaked in logs. Docker secrets are mounted as read-only files in `/run/secrets/<name>` inside only the containers that need them, and are never baked into an image or shown in `docker inspect`. This project therefore keeps **all passwords in secrets** (`secrets/*.txt`) and only non-sensitive settings (domain, usernames, DB name) in `srcs/.env`.

**Docker Network vs Host Network.** With `network_mode: host` a container shares the host's network stack: no isolation and port clashes with the host. A user-defined bridge network gives each container its own IP and DNS name (`mariadb`, `wordpress`), keeps the database and PHP-FPM unreachable from outside, and lets us publish only port 443. This project uses a bridge network, and `host`, `--link` and `links:` are not used.

**Docker Volumes vs Bind Mounts.** A bind mount maps an arbitrary host path into a container and depends on the host's directory layout and permissions. A named volume is managed by Docker and referenced by name. Here we use **named volumes** (`mariadb_data`, `wordpress_data`) configured with the `local` driver so that their data lives at a known place on the host, `/home/<login>/data/{mariadb,wordpress}`, as the subject requires, while the compose file still refers to them by volume name.

## Instructions

### Prerequisites

- Linux host with Docker Engine and the Docker Compose v2 plugin (`docker compose`)
- `make`, `openssl`, and `sudo` (only needed by `make fclean`)
- Your user must be allowed to run `docker`

### 1. Point the domain at your machine

```bash
echo "127.0.0.1 yafahfou.42.fr" | sudo tee -a /etc/hosts
```

### 2. Configure

- Create `srcs/.env` with the domain, DB name/user and WordPress usernames/e-mails. It is **not committed**. The template is in [DEV_DOC.md](DEV_DOC.md#create-srcsenv).
- Passwords live in `secrets/` and are **not committed** (see [.gitignore](.gitignore)). `make` creates any missing file with a random password. To choose your own instead, create these four files first, one password per file:

  ```
  secrets/db_root_password.txt
  secrets/db_password.txt
  secrets/wp_admin_password.txt
  secrets/wp_user_password.txt
  ```

### 3. Build and run

```bash
make          # generate missing secrets, create data dirs, build images, start containers
```

Then open **https://yafahfou.42.fr** (accept the self-signed certificate warning). The admin panel is at `/wp-admin`.

### Makefile targets

| Target        | Action                                                                    |
|---------------|---------------------------------------------------------------------------|
| `make`        | `build` + `up`                                                            |
| `make build`  | Create missing secrets and data dirs, build the images                    |
| `make up`     | Start the containers in the background                                    |
| `make down`   | Stop and remove the containers (data is kept)                             |
| `make stop` / `make start` | Stop / start containers without removing them                |
| `make logs` / `make ps`    | Follow logs / show container status                          |
| `make clean`  | `down` + remove this project's images                                     |
| `make fclean` | `clean` + remove this project's volumes **and `/home/<login>/data`** (all site and DB data is lost) |
| `make re`     | `fclean` then `all`                                                       |

More detail: [USER_DOC.md](USER_DOC.md) (using the site) and [DEV_DOC.md](DEV_DOC.md) (working on the project).

## Project layout

```
.
├── Makefile
├── secrets/                       # passwords, one per file (git-ignored)
└── srcs/
    ├── .env                       # non-sensitive settings
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/   (Dockerfile, conf/50-server.cnf, tools/init_db.sh)
        ├── nginx/     (Dockerfile, conf/nginx.conf, tools/generate_ssl.sh)
        └── wordpress/ (Dockerfile, conf/www.conf, tools/setup_wordpress.sh)
```

## Resources

- [Docker documentation](https://docs.docker.com/) and [Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Docker secrets in Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [Dockerfile best practices](https://docs.docker.com/build/building/best-practices/), including the PID 1 / foreground-process problem
- [NGINX documentation](https://nginx.org/en/docs/), [`ngx_http_ssl_module`](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [WP-CLI handbook](https://make.wordpress.org/cli/handbook/), [Installing WordPress](https://developer.wordpress.org/advanced-administration/before-install/howto-install/)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/documentation/)
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)

### Use of AI

Claude (Anthropic's Claude Code) was used to review the project before submission, to help fix the issues found (secrets not being applied to MariaDB/WordPress, a WordPress-install race on first boot, an over-broad `make clean`), and to draft this README, `USER_DOC.md` and `DEV_DOC.md`. Every change was tested by building and running the stack from scratch, and the author is responsible for and able to explain all of the content.

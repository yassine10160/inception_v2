# User Documentation

How to run and use the Inception website as an administrator or evaluator. For building or modifying the project, see [DEV_DOC.md](DEV_DOC.md).

## Services provided

| Service     | What it does                                                        |
|-------------|---------------------------------------------------------------------|
| `nginx`     | Web server. Serves the site over HTTPS on port 443 (TLS 1.2 / 1.3). |
| `wordpress` | The WordPress application (PHP-FPM).                                |
| `mariadb`   | The database that stores posts, pages, users and settings.          |

The stack is a WordPress website reachable at **https://yafahfou.42.fr**. Only the HTTPS port (443) is open to the outside. The database and PHP-FPM are private to the Docker network.

## Start and stop

Run these from the project root:

| Goal                                   | Command       |
|----------------------------------------|---------------|
| Start the project (first time: builds) | `make`        |
| Stop it, keeping all data              | `make down`   |
| Pause / resume without removing        | `make stop` / `make start` |
| Erase everything, including site data  | `make fclean` |

The first start takes a minute or two: WordPress is downloaded and installed automatically. After that, restarts take seconds and content is preserved.

> **Warning:** `make fclean` and `make re` permanently delete the database and all uploaded files.

## Access the website

1. Make sure the domain resolves to your machine (once):
   ```bash
   echo "127.0.0.1 yafahfou.42.fr" | sudo tee -a /etc/hosts
   ```
2. Open **https://yafahfou.42.fr** in a browser.
3. The certificate is self-signed, so the browser shows a warning. Choose *Advanced → Proceed* (this is expected).

Plain `http://` is not served. Always use `https://`.

**Administration panel:** https://yafahfou.42.fr/wp-admin

## Accounts and credentials

Two WordPress accounts are created automatically on first start:

| Account       | Role          | Username                                | Password file                  |
|---------------|---------------|-----------------------------------------|--------------------------------|
| Administrator | administrator | `WP_ADMIN_USER` in [srcs/.env](srcs/.env) (`pierrot`) | `secrets/wp_admin_password.txt` |
| Regular user  | author        | `WP_USER` in [srcs/.env](srcs/.env) (`someone`)       | `secrets/wp_user_password.txt`  |

Where things are kept:

- **Usernames and e-mails**: [srcs/.env](srcs/.env)
- **Passwords**: `secrets/*.txt`, one password per file. Read one with `cat secrets/wp_admin_password.txt`. These files are private to your machine and are never committed to git.
  - `db_root_password.txt`: MariaDB root
  - `db_password.txt`: the WordPress database user
  - `wp_admin_password.txt`, `wp_user_password.txt`: the two WordPress accounts

Secrets are read **only when the site is first installed**. Changing a file afterwards does not change existing passwords. To change a WordPress password, use *Users → Profile* in the admin panel (or `wp user update` as shown below). To re-create everything with new secrets, run `make re` (this erases all data).

```bash
docker exec wordpress wp user update <username> --user_pass='<new password>' --path=/var/www/html --allow-root
```

## Check that everything is running

```bash
make ps
```

All three services (`mariadb`, `wordpress`, `nginx`) should show `Up`. Quick end-to-end test:

```bash
curl -k -I https://yafahfou.42.fr     # expect: HTTP/1.1 200 OK
```

Follow logs with `make logs`, or for one service: `docker logs nginx`, `docker logs wordpress`, `docker logs mariadb`.

## Common tasks

- **Write a post / page:** log in at `/wp-admin` → *Posts* or *Pages* → *Add New*.
- **Upload media, install themes/plugins:** through the admin dashboard (uploads up to 64 MB).
- **Add a user:** *Users → Add New*.

## Troubleshooting

| Symptom                                   | What to do                                                                                                   |
|-------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| Browser cannot find `yafahfou.42.fr`      | Add the `/etc/hosts` line above.                                                                             |
| Connection refused                        | `make ps`: is `nginx` up? Is something else already using port 443? Run `make up`.                          |
| `502 Bad Gateway`                         | WordPress is still starting or has stopped. Wait a few seconds, then check `docker logs wordpress`.          |
| "Error establishing a database connection" | Check `docker logs mariadb`. Make sure the secrets were not modified after the first install.               |
| First start seems stuck                   | Normal for up to a minute or two (downloading WordPress). Watch `make logs`.                                 |
| Need a completely fresh site              | `make re` (**erases all data**).                                                                             |

If you ask for help, include the output of `make ps` and the logs of the three services.

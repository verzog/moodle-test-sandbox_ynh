# moodle-test-sandbox_ynh

A sandbox for testing **unsupported / development versions of Moodle** in Docker,
isolated from any real server. The first setup here runs **Moodle 5.3** with the
PostgreSQL 17 version it needs — something YunoHost 12 (Debian 12) can't run
natively — without touching your host's packages, database, or other apps.

> **This is a throwaway test environment, not a YunoHost package.** It does not
> use YunoHost's SSO/LDAP and is not meant for production data. It exists so you
> can explore new Moodle versions safely before they're officially supported.

**In a hurry?** See [`QUICKSTART.md`](QUICKSTART.md) for the abbreviated steps.

## Why Docker instead of the YunoHost package?

Moodle 5.3 requires PostgreSQL 17, but Debian 12 (YunoHost 12) ships only
PostgreSQL 15. Docker bundles the correct PostgreSQL **inside the container**, so
your host's packages and shared database are never changed. See the repo
discussion for the full reasoning.

## Release timing

Moodle 5.3 is an **LTS** release. Stable is scheduled for **5 October 2026**.
Until then Moodle has not cut the `MOODLE_503_STABLE` branch, so the 5.3 code
lives on the development branch **`main`** — which is why `MOODLE_BRANCH` defaults
to `main`. Once 5.3 is released, set `MOODLE_BRANCH=MOODLE_503_STABLE` in your
`.env` to follow the stable 5.3 line instead.

## Requirements

- A machine with **Docker** and the **Docker Compose plugin** installed.
- That's it. No changes are made outside Docker.

## Quick start

```bash
# 1. Clone this repo and go into it
git clone https://github.com/verzog/moodle-test-sandbox_ynh.git
cd moodle-test-sandbox_ynh

# 2. Create your settings file and edit the two passwords
cp .env.example .env
#    (open .env, change DB_PASS and MOODLE_ADMIN_PASS)

# 3. Build and start (first build downloads Moodle + PHP; takes a few minutes)
docker compose up -d --build

# 4. Watch the install finish
docker compose logs -f moodle
#    Wait for: "Moodle installed."  then press Ctrl+C
```

Open <http://localhost:8080> and log in as **admin** with the password you set
in `MOODLE_ADMIN_PASS`.

> Running on a remote server instead of your own machine? Set `MOODLE_WWWROOT`
> in `.env` to `http://SERVER_IP:8080` before step 3, and make sure port 8080
> is reachable.

## Everyday commands

```bash
docker compose stop            # pause (keeps all data)
docker compose start           # resume
docker compose down            # stop and remove containers (data volumes kept)
docker compose down -v         # delete EVERYTHING including the database
docker compose logs -f moodle  # view Moodle logs
```

## Trying stable once it's released (5 Oct 2026)

After 5.3 is released, set `MOODLE_BRANCH=MOODLE_503_STABLE` in your `.env` to
follow the stable 5.3 line, then rebuild to pull the latest 5.3 code:

```bash
docker compose up -d --build   # rebuilds with the newest 5.3 source
```

Then open the site and complete the upgrade prompt if one appears.

## Serving it over HTTPS with a YunoHost domain

The container itself only speaks plain HTTP on `HTTP_PORT`. To reach it over
HTTPS at a real domain, let YunoHost's nginx terminate TLS and reverse-proxy to
the container:

1. **Create the subdomain** in YunoHost (Domains → Add) and install its
   Let's Encrypt certificate.
2. In `.env`, set:
   ```
   MOODLE_WWWROOT=https://YOUR_SUBDOMAIN
   MOODLE_SSLPROXY=true
   BIND_HOST=127.0.0.1
   ```
   `MOODLE_SSLPROXY=true` stops the redirect loop that happens when nginx serves
   HTTPS but the container receives HTTP; `BIND_HOST=127.0.0.1` keeps port 8080
   private so only the local proxy can reach it.
3. Build with the new settings so the HTTPS wwwroot is baked into the install.
   On a fresh site: `docker compose up -d --build`. (If the site was already
   installed with a different wwwroot, use `docker compose down -v` first to
   reinstall cleanly - this erases the test data.)
4. Add an nginx rule for the domain that **reverse-proxies to the container and
   bypasses YunoHost's SSO** in one go. YunoHost reads extra rules from
   `/etc/nginx/conf.d/YOUR_SUBDOMAIN.d/`, and the HTTPS server block has no
   `location /` of its own, so this slots in cleanly (replace the domain/port to
   match your `.env`):
   ```bash
   sudo mkdir -p /etc/nginx/conf.d/YOUR_SUBDOMAIN.d
   sudo tee /etc/nginx/conf.d/YOUR_SUBDOMAIN.d/moodle-docker.conf > /dev/null <<'EOF'
   location / {
       # Bypass YunoHost SSO for this domain (Moodle has its own login).
       # A NON-EMPTY access_by_lua_block is required - an empty {} is ignored
       # and the inherited SSOwat handler still runs.
       access_by_lua_block {
           ngx.log(ngx.INFO, "moodle sandbox: bypassing YunoHost SSO")
       }
       proxy_pass http://127.0.0.1:8080;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection $connection_upgrade;
       client_max_body_size 100M;
   }
   EOF
   sudo nginx -t && sudo systemctl reload nginx
   ```
   Always let `nginx -t` pass before the reload - a bad rule affects every site
   on the server.

   > **Why the Lua block?** On **YunoHost 12** the SSO was rewritten and ignores
   > the old `/etc/ssowat/conf.json.persistent` `skipped_urls` trick, so the
   > nginx `access_by_lua_block` override above is the reliable way to stop the
   > SSO redirect. (On older YunoHost 11 the `skipped_urls` approach also works;
   > the nginx override works on both.)
5. Verify: `curl -I https://YOUR_SUBDOMAIN` should return `HTTP/2 200` or a `303`
   to `…/login/index.php` (Moodle's own login), with **no `x-sso-wat` header and
   no `:8080` in any redirect**. Then open the site in a browser (hard refresh).
   - Still see `x-sso-wat`? The SSO bypass isn't applied - recheck step 4.
   - Redirect to `…:8080`? The site was installed with the wrong `wwwroot`
     (e.g. built before `.env` was set). Fix `MOODLE_WWWROOT`, then
     `docker compose down -v && docker compose up -d --build` to reinstall.

## PHP settings and cron (config-panel equivalents)

The stack mirrors the YunoHost package's config panel through `.env`:

| `.env` variable | Default | Equivalent setting |
|---|---|---|
| `PHP_MEMORY_LIMIT` | `256M` | PHP memory limit per process |
| `PHP_UPLOAD_MAX_FILESIZE` | `1G` | upload_max_filesize / post_max_size |
| `PHP_MAX_EXECUTION_TIME` | `300` | PHP max execution time (seconds) |
| `PHP_MAX_INPUT_VARS` | `5000` | PHP max input vars (Moodle needs ≥ 5000) |
| `CRON_INTERVAL` | `15` | Minutes between Moodle cron runs |

Edit `.env`, then apply with:

```bash
docker compose up -d          # recreates containers with the new values
```

Moodle's scheduled tasks run from a **background cron loop inside the moodle
container** (`admin/cli/cron.php` every `CRON_INTERVAL` minutes, as `www-data`).
Running cron in the same container as the web server means it always uses the
same code and database - it can't drift onto a different build. Cron output
appears in the container log; run cron once on demand with:

```bash
docker compose exec moodle runuser -u www-data -- php /var/www/html/admin/cli/cron.php
```

> Moodle expects cron every 1 minute and warns if it runs less often, so
> `CRON_INTERVAL=1` keeps its health check happy (the YunoHost package defaults
> to 15).

> Behind a reverse proxy, uploads are also limited by the proxy's
> `client_max_body_size` (the YunoHost nginx snippet sets `100M`); raise it there
> too if you increase `PHP_UPLOAD_MAX_FILESIZE`.

## Notes / limitations

- Apache serves from Moodle's `public/` subdirectory (required from Moodle 5.1+);
  `config.php` lives at the project root, outside the web root.
- The image runs `composer install` (git checkouts ship without `vendor/`) and
  configures Moodle's router (`r.php` rewrite + `$CFG->routerconfigured`), so the
  admin health checks for Composer and the router pass.
- Internal paths (`.git`, `.github`, `behat`, `node_modules`, `vendor`) return a
  404 before the router catch-all, so Moodle's "public/private paths" security
  check passes.
- No email delivery is configured (fine for testing).
- The container serves plain HTTP; use the YunoHost/HTTPS setup above (or keep it
  to `http://SERVER_IP:HTTP_PORT` for local testing). Don't expose the raw HTTP
  port to the internet.
- The admin password and DB password live in `.env`; keep that file private and
  do not commit your real `.env` (only `.env.example` is tracked).

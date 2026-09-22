# Quick start

Abbreviated install for the Moodle 5.3 Docker sandbox. Needs **Docker** + the
**Docker Compose plugin**. The full details are in [`README.md`](README.md).

The example domain below is `learn.scca.nohost.me` — replace it with your own.

## 1. Get the code and configure

```bash
git clone https://github.com/verzog/moodle-test-sandbox_ynh.git
cd moodle-test-sandbox_ynh
cp .env.example .env
nano .env
```

Set in `.env`:

```
MOODLE_WWWROOT=https://learn.scca.nohost.me
MOODLE_ADMIN_PASS=<choose-a-strong-password>
DB_PASS=<choose-a-strong-password>
MOODLE_SSLPROXY=true
BIND_HOST=127.0.0.1
CRON_INTERVAL=1
```

> For a quick local test without a domain, use `MOODLE_WWWROOT=http://SERVER_IP:8080`,
> `MOODLE_SSLPROXY=false`, `BIND_HOST=0.0.0.0`, and skip step 2.

## 2. On the YunoHost host (HTTPS via your domain)

**a. Domain + certificate** — YunoHost admin → **Domains → Add**
`learn.scca.nohost.me`, then install its **Let's Encrypt** certificate.

**b. Reverse-proxy the domain to the container:**

```bash
sudo mkdir -p /etc/nginx/conf.d/learn.scca.nohost.me.d
sudo tee /etc/nginx/conf.d/learn.scca.nohost.me.d/moodle-docker.conf >/dev/null <<'EOF'
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    client_max_body_size 100M;
}
EOF
sudo nginx -t && sudo systemctl reload nginx
```

**c. Let SSO skip the domain** (Moodle has its own login):

```bash
F=/etc/ssowat/conf.json.persistent
[ -s "$F" ] || echo '{}' | sudo tee "$F" >/dev/null
sudo jq '.skipped_urls=((.skipped_urls//[])+["learn.scca.nohost.me/"]|unique)' \
    "$F" | sudo tee "$F.tmp" >/dev/null && sudo mv "$F.tmp" "$F"
sudo yunohost app ssowatconf
```

## 3. Build and start

```bash
docker compose up -d --build
docker compose logs -f moodle    # wait for "Moodle installed.", then Ctrl+C
```

## 4. Verify and log in

```bash
curl -I https://learn.scca.nohost.me     # expect HTTP/2 200, no x-sso-wat header
```

Open <https://learn.scca.nohost.me> and log in as **admin** with your
`MOODLE_ADMIN_PASS`.

## Handy commands

```bash
docker compose up -d          # apply .env changes
docker compose logs -f moodle # logs (web + cron)
docker compose down           # stop (keeps data)
docker compose down -v        # wipe everything (fresh install next time)
```

# moodle-test-sandbox_ynh

A sandbox for testing **unsupported / development versions of Moodle** in Docker,
isolated from any real server. The first setup here runs **Moodle 5.3** with the
PostgreSQL 17 version it needs — something YunoHost 12 (Debian 12) can't run
natively — without touching your host's packages, database, or other apps.

> **This is a throwaway test environment, not a YunoHost package.** It does not
> use YunoHost's SSO/LDAP and is not meant for production data. It exists so you
> can explore new Moodle versions safely before they're officially supported.

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

## Notes / limitations

- No email delivery is configured (fine for testing).
- No HTTPS - this is plain HTTP for local testing only. Do not expose it to the
  internet as-is.
- The admin password and DB password live in `.env`; keep that file private and
  do not commit your real `.env` (only `.env.example` is tracked).

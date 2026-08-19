# KuraNotes

Private notes as a Rails 8 PWA. One SQLite file, no Redis.

## Local

```bash
bin/setup
bin/dev
```

Open http://127.0.0.1:3000

## VPS (Docker Compose)

On the server, with Docker installed:

```bash
cp .env.example .env
# paste config/master.key into RAILS_MASTER_KEY
# set KURA_HOST to your domain
docker compose up -d --build
```

Create the first account in the browser, then lock signup:

```bash
# in .env
SIGNUP_ENABLED=false
docker compose up -d
```

`docker compose restart` does **not** reload `.env`. Use `up -d`.

### Users on the server

```bash
docker compose exec web bin/rails kura:users
docker compose exec web bin/rails kura:create EMAIL=you@x.com PASSWORD='at-least-8'
docker compose exec web bin/rails kura:password EMAIL=you@x.com PASSWORD='new-secret'
```

### Proxy (Caddy or nginx)

Nothing is bundled. The app listens on `127.0.0.1:3000` and does not bind 80/443. Point your own Caddy or nginx at that address, set `FORCE_SSL=true` in `.env`, then `docker compose up -d`.

Notes live in the `kura_data` volume (`storage/production.sqlite3`). Back that up.

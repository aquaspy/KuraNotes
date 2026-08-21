# KuraNotes

Private notes as a Rails 8 PWA. One SQLite file, no Redis.

## Local

```bash
bin/setup
bin/dev
```

Open http://127.0.0.1:3000

A `config/master.key` is created by `rails new` and is gitignored. Keep that file. If you cloned this repo and have no key:

```bash
rm -f config/credentials.yml.enc
EDITOR=true bin/rails credentials:edit
```

That writes a new `config/master.key`. Do not commit it.

## VPS (Docker Compose)

On the server, with Docker installed:

```bash
cp .env.example .env
# set SECRET_KEY_BASE (see below) and KURA_HOST
docker compose up -d --build
```

Create the first account in the browser, then lock signup:

```bash
# in .env
SIGNUP_ENABLED=false
docker compose up -d
```

`docker compose restart` does **not** reload `.env`. Use `up -d`.

### Secret

Pick **one**. You do not need both.

**Compose (recommended on a VPS):**

```bash
openssl rand -hex 64
```

Put the output in `.env` as `SECRET_KEY_BASE`. No `master.key` required.

**Rails credentials** (if you already have a key, or want `rails credentials:edit`):

```bash
rm -f config/credentials.yml.enc
EDITOR=true bin/rails credentials:edit
cat config/master.key
```

Put that value in `.env` as `RAILS_MASTER_KEY`. A random hex will not decrypt the `credentials.yml.enc` that ships in git — generate a new pair as above, or use `SECRET_KEY_BASE` instead.

Losing the key does not lose notes. It only invalidates session cookies. Generate a new one and users sign in again.

### Users on the server

```bash
docker compose exec web bin/rails kura:users
docker compose exec web bin/rails kura:create EMAIL=you@x.com PASSWORD='at-least-8'
docker compose exec web bin/rails kura:password EMAIL=you@x.com PASSWORD='new-secret'
```

### Proxy (Caddy or nginx)

Nothing is bundled. The app listens on `127.0.0.1:3000` and does not bind 80/443. Point your own Caddy or nginx at that address, set `FORCE_SSL=true` in `.env`, then `docker compose up -d`.

Notes live in the `kura_data` volume (`storage/production.sqlite3`). Back that up.

Offline, the PWA can reopen the home page and any note you already opened while online. Edits stay on screen and save when you are back online. Sign out wipes the cache so a second person on the same browser cannot read the previous user’s notes offline.

### Import / export

**Export** downloads a JSON file of every note on the account.

**Import** accepts one or more files (or a zip). It recognizes:

- KuraNotes JSON (the export above)
- Notesnook **text** export (the unzipped `.txt` files, or the original `.zip`)
- Standard Notes **unencrypted** backup (`Standard Notes Backup and Import File.txt`, or the zip it came in). Super notes are converted to plaintext. Tags become folders.

Encrypted Standard Notes backups are skipped. Import does not replace existing notes; it adds them. Cap is 500 notes per import.

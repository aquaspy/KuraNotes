# KuraNotes

**Your notes. Your VPS. Nothing else in the middle.**

KuraNotes is a private notes app you run yourself. It is a Rails 8 PWA that lives on a single SQLite file — no Redis, no SaaS account, no “sync cloud” you did not choose. Open it from your phone or laptop, write, close the tab. Come back later. That is the whole product.

---

## Philosophy

Most note apps grow into platforms. Folders become workspaces. Workspaces become teams. Teams become billing. Somewhere along the way the text you wrote stops feeling like *yours*.

KuraNotes goes the other direction.

- **Quiet by design.** Plain text, folders if you want them, a lock screen when you walk away. No AI sidebar, no collaborative cursors, no growth dashboard.
- **Yours to host.** One Docker Compose stack on a VPS you control. The database is a file. Back it up like any other file.
- **Honest about privacy.** Notes sit as plaintext in SQLite on *your* machine. There is no end-to-end encryption theater — the trust boundary is the server you run.
- **Small enough to understand.** Rails, SQLite, a service worker. If something breaks at 2 a.m., you can actually read the code.

It is part of the **Kura** family: the same calm auth, idle lock, PWA offline reads, and Compose-on-localhost pattern as [KuraChat](https://github.com/aquaspy/KuraChat), [KuraHome](https://github.com/aquaspy/KuraHome), [KuraCalendar](https://github.com/aquaspy/KuraCalendar), and [KuraSpend](https://github.com/aquaspy/KuraSpend). Each app keeps its own database and volume on purpose.

---

## What you get

- Multi-user accounts on one instance (family, friends, just you)
- Folders, share links (`/s/...`), import & export
- Import from **Notesnook** text exports and **Standard Notes** unencrypted backups
- PWA: reopen notes you already viewed while offline; edits wait for the network and save when you are back
- Long-lived sessions with an idle lock; sign-out wipes the offline cache

**What you do not get (on purpose):** CalDAV-style sync protocols, E2E encryption, outbound email password reset, or a bundled reverse proxy. You bring your own Caddy or nginx.

---

## Self-host (Docker Compose)

You need Docker on a VPS (or a home box). The app binds to localhost only — port 80/443 stay free for your proxy.

```bash
git clone https://github.com/aquaspy/KuraNotes.git
cd KuraNotes
cp .env.example .env
```

Edit `.env`. At minimum:

```bash
SECRET_KEY_BASE=          # paste: openssl rand -hex 64
KURA_HOST=notes.example.com
SIGNUP_ENABLED=true       # first account, then flip to false
FORCE_SSL=false           # true once HTTPS terminates in front
BIND=127.0.0.1:3000       # change the port if another Kura app already took 3000
```

Then:

```bash
docker compose up -d --build
```

Open the app (e.g. `http://127.0.0.1:3000`), create the first account in the browser — **or** from the shell:

```bash
docker compose exec web bin/rails kura:create EMAIL=you@example.com PASSWORD='at-least-8'
```

Lock public signup so the internet cannot mint accounts on your box:

```bash
# in .env
SIGNUP_ENABLED=false
docker compose up -d
```

> **Important:** `docker compose restart` does **not** reload `.env`. Always use `docker compose up -d` after changing environment variables.

### Secrets

Pick **one**. You do not need both.

| Approach | When | How |
| --- | --- | --- |
| **`SECRET_KEY_BASE`** (recommended) | Compose / VPS | `openssl rand -hex 64` → put in `.env` |
| **`RAILS_MASTER_KEY`** | You prefer Rails credentials | Regenerate with `EDITOR=true bin/rails credentials:edit`, then put `config/master.key` in `.env` as `RAILS_MASTER_KEY` |

A random hex will **not** decrypt the `credentials.yml.enc` that ships in git. Either use `SECRET_KEY_BASE`, or generate a fresh credentials pair.

Losing the key does **not** lose notes. It only invalidates session cookies. Generate a new one and sign in again.

### Reverse proxy (Caddy or nginx)

Nothing is bundled. Point your proxy at whatever `BIND` you chose, set `FORCE_SSL=true`, then `docker compose up -d`.

**Caddy:**

```
notes.example.com {
  reverse_proxy 127.0.0.1:3000
}
```

**nginx:**

```
location / {
  proxy_pass http://127.0.0.1:3000;
  proxy_http_version 1.1;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-Proto $scheme;
}
```

### Users on the server

There is no email recovery. Reset passwords from the box:

```bash
docker compose exec web bin/rails kura:users
docker compose exec web bin/rails kura:create EMAIL=you@example.com PASSWORD='at-least-8'
docker compose exec web bin/rails kura:password EMAIL=you@example.com PASSWORD='new-secret'
```

### Backup

Notes live in the `kura_data` volume (`storage/production.sqlite3`). Back that up.

```bash
docker compose exec web tar -C /rails/storage -cf - . > kuranotes-backup.tar
```

### Shared browsers

Sign out **and** wait for the cache wipe. Until then, another person who opens the PWA offline can see cached pages from the previous user.

---

## Import / export

**Export** downloads a JSON file of every note on the account.

**Import** accepts one or more files (or a zip). It recognizes:

- KuraNotes JSON (the export above)
- Notesnook **text** export (unzipped `.txt` files, or the original `.zip`)
- Standard Notes **unencrypted** backup (`Standard Notes Backup and Import File.txt`, or the zip it came in). Super notes become plaintext. Tags become folders.

Encrypted Standard Notes backups are skipped. Import **adds** notes; it does not replace existing ones. Cap is 500 notes per import.

---

## Local development

```bash
bin/setup
bin/dev
```

Open http://127.0.0.1:3000

A `config/master.key` is created by `rails new` and is gitignored. Keep it. If you cloned the repo and have no key:

```bash
rm -f config/credentials.yml.enc
EDITOR=true bin/rails credentials:edit
```

That writes a new `config/master.key`. Do not commit it.

---

## Environment

| Variable | What it does |
| --- | --- |
| `SECRET_KEY_BASE` | Session cookies (Compose). `openssl rand -hex 64` |
| `RAILS_MASTER_KEY` | Alternative to `SECRET_KEY_BASE` when using credentials |
| `SIGNUP_ENABLED` | Public signup form. Turn off after the first account |
| `FORCE_SSL` | `true` when Caddy/nginx terminates HTTPS |
| `KURA_HOST` | Public hostname (comma-separated if several) |
| `BIND` | Default `127.0.0.1:3000` |

---

## Sister apps

| App | Role |
| --- | --- |
| [KuraChat](https://github.com/aquaspy/KuraChat) | Private chat with Grok |
| [KuraHome](https://github.com/aquaspy/KuraHome) | Quiet start-page / homepage |
| [KuraCalendar](https://github.com/aquaspy/KuraCalendar) | Personal calendar & birthdays |
| [KuraSpend](https://github.com/aquaspy/KuraSpend) | Subscriptions & daily spend |

Same spirit. Separate databases. Your stack, your rules.

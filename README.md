# KuraNotes

**Your notes. Your VPS. Nothing else in the middle.**

KuraNotes is a private notes app you run yourself. It is a Go PWA that lives on a single SQLite file — no Redis, no SaaS account, no “sync cloud” you did not choose. Open it from your phone or laptop, write, close the tab. Come back later. That is the whole product.

One static Go binary (~14 MB, ~20 MB RAM) serves the whole app: pages, import/export, the JSON API, and the PWA shell.

---

## Philosophy

Most note apps grow into platforms. Folders become workspaces. Workspaces become teams. Teams become billing. Somewhere along the way the text you wrote stops feeling like *yours*.

KuraNotes goes the other direction.

- **Quiet by design.** Plain text, folders if you want them, a lock screen when you walk away. No AI sidebar, no collaborative cursors, no growth dashboard.
- **Yours to host.** One Docker Compose stack on a VPS you control. The database is a file. Back it up like any other file.
- **Honest about privacy.** Notes sit as plaintext in SQLite on *your* machine. There is no end-to-end encryption theater — the trust boundary is the server you run.
- **Small enough to understand.** Go, SQLite, a service worker. If something breaks at 2 a.m., you can actually read the code.

It is part of the **Kura** family: the same calm shell as [KuraChat](https://github.com/aquaspy/KuraChat) — cookie auth, idle lock (per device), PWA offline reads, and Compose-on-localhost — plus [KuraHome](https://github.com/aquaspy/KuraHome), [KuraCalendar](https://github.com/aquaspy/KuraCalendar), and [KuraSpend](https://github.com/aquaspy/KuraSpend). Each app keeps its own database and volume on purpose.

---

## What you get

- Multi-user accounts on one instance (family, friends, just you)
- Folders, share links (`/s/...`), import & export
- API tokens + JSON API for AI agents (see API.md)
- Import from **Notesnook** text exports and **Standard Notes** unencrypted backups
- PWA: reopen notes you already viewed while offline; edits wait for the network and save when you are back
- Long-lived sessions with an optional idle lock (**per device**, not synced in the account DB); sign-out wipes the offline cache

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
docker compose exec -e EMAIL=you@example.com -e PASSWORD='at-least-8' web ./kuranotes create
```

Lock public signup so the internet cannot mint accounts on your box:

```bash
# in .env
SIGNUP_ENABLED=false
docker compose up -d
```

> **Important:** `docker compose restart` does **not** reload `.env`. Always use `docker compose up -d` after changing environment variables.

There are no cookie-signing secrets to manage: sessions are opaque random ids in SQLite. Losing the database loses everything; losing anything else loses nothing.

### Coming from the Rails version

The Go app reads its own `kuranotes.sqlite3`, so the Rails database is imported once:

```bash
# 1. Back up the old volume.
docker compose exec web tar -C /rails/storage -cf - . > kuranotes-rails-backup.tar

# 2. Deploy the Go image (same kura_notes_data volume, now mounted at /data).
docker compose up -d --build

# 3. Import the old database into the new layout.
docker compose exec web ./kuranotes import /data/production.sqlite3

# 4. Verify in the browser, then delete the legacy file:
#    /data/production.sqlite3*.
```

Users keep their passwords, notes, folders, share links, and API tokens (same `kura_…` values — agents keep working). Everyone signs in again (sessions are not imported).

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
docker compose exec web ./kuranotes users
docker compose exec -e EMAIL=you@example.com -e PASSWORD='at-least-8' web ./kuranotes create
docker compose exec -e EMAIL=you@example.com -e PASSWORD='new-secret' web ./kuranotes password
```

### Backup

Notes live in the `kura_notes_data` volume (`/data/kuranotes.sqlite3`). Back that up.

```bash
docker compose exec web tar -C /data -cf - . > kuranotes-backup.tar
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

## AI agents (API)

KuraNotes is ready for the agentic era: mint a token under **More → API tokens**, hand it to OpenClaw, Hermes Agent, or any HTTP client, and it can read, write, and file notes into folders — even while the app is locked. See [API.md](API.md) for endpoints, curl examples, and a setup snippet.

---

## Local development

You need Go 1.27+, plus the `templ` and `tailwindcss` binaries:

```bash
go install github.com/a-h/templ/cmd/templ@latest
# tailwindcss: https://github.com/tailwindlabs/tailwindcss/releases
```

Then:

```bash
templ generate
tailwindcss --input web/static/css/input.css --output web/static/css/app.css
go run ./cmd/kuranotes serve
```

Open http://127.0.0.1:3000

```bash
go test ./...   # suite: store, importer, HTTP flows, API
go vet ./...
```

---

## Environment

| Variable | What it does |
| --- | --- |
| `SIGNUP_ENABLED` | Public signup form. Turn off after the first account |
| `FORCE_SSL` | `true` when Caddy/nginx terminates HTTPS |
| `KURA_HOST` | Public hostname (comma-separated if several) |
| `BIND` | Default `127.0.0.1:3000` |
| `DATA_DIR` | Where `kuranotes.sqlite3` lives. Default `storage` (`/data` in Docker) |

---

## Sister apps

| App | Role |
| --- | --- |
| [KuraChat](https://github.com/aquaspy/KuraChat) | Private chat with your model |
| [KuraHome](https://github.com/aquaspy/KuraHome) | Quiet start-page / homepage |
| [KuraCalendar](https://github.com/aquaspy/KuraCalendar) | Personal calendar & birthdays |
| [KuraSpend](https://github.com/aquaspy/KuraSpend) | Subscriptions & daily spend |

Same spirit. Separate databases. Your stack, your rules.

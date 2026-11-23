# Inbar — portfolio site

A blueprint-style photo portfolio fed by a shared Google Photos album.

- `index.html` — the whole site (no build step).
- `photos.js` — the album's photo list. Regenerated daily by `.github/workflows/sync.yml` (and by `sync.ps1` locally).
- `assets/` — the black logo.
- `sync.ps1` — reads the album and writes `photos.js`. The album share link comes from the `ALBUM_URL` secret
  (GitHub) or a local, git-ignored `album-url.txt`.
- `serve.ps1` — optional local preview server (`-Lan` lets a phone on the same Wi-Fi open it).

Texts to edit (name, About paragraphs, email) are in the `SITE` block near the top of the script in `index.html`.

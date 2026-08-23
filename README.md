# Omashelf

A reading tracker for the [Omarchy](https://omarchy.org/) shell. The bar shows
how far you are into the book you're reading; the popup is a small reading
dashboard plus your whole shelf.

![Omashelf panel](preview.png)

## What it does

- **Bar pill** — book icon plus the remaining/completed percentage of your
  current read. Scroll it or right/middle-click it to log a page without
  opening anything.
- **Now reading** — title, author, a progress track, page count, pages left,
  and an estimated "~N days left" based on your recent pace.
- **Mini dashboard** — pages today, pages over 7 days, current reading streak,
  and books finished this year, with a seven-day bar chart.
- **Shelf** — every book with its own progress track. Finished books are
  hidden until you ask for them.
- **Add books** from the panel, or from the bundled `omashelf` CLI.

Everything is stored in one JSON file that the widget watches, so the panel and
the CLI stay in sync without a restart.

## Install

```bash
omarchy plugin add https://github.com/daniel-felipe/omarchy-plugin-omashelf.git
omarchy plugin enable io.github.daniel-felipe.omashelf
```

Plugins land disabled so you can read the source first. To move the pill:

```bash
omarchy bar move io.github.daniel-felipe.omashelf --section right
```

## Remove

```bash
omarchy plugin disable io.github.daniel-felipe.omashelf
omarchy plugin remove io.github.daniel-felipe.omashelf
```

Your library file is left alone; delete
`~/.local/state/omarchy/omashelf/library.json` if you want it gone too.

## Keyboard

Inside the panel:

| Key | Action |
|-----|--------|
| `j` / `k` (or arrows) | Move through the shelf |
| `Enter` | Make the highlighted book the current read |
| `+` / `-` | Log one page forward/back |
| `]` / `[` | Log a big step (10 pages by default) |
| `a` | Add a book |
| `f` | Mark the highlighted book finished |
| `p` | Pause/resume the highlighted book |
| `v` | Show or hide finished books |
| `x` | Remove — press twice, the first press only arms it |
| `Esc` | Close |

Page keys act on the highlighted book once you've moved the cursor, and on
your current read before that; the controls row names the book when the two
differ.

Mouse: click a row to make it current, right-click to jump a big step forward,
middle-click to go back, scroll for single pages.

## CLI

`bin/omashelf` edits the same library file:

```bash
omashelf add "Dune" 412 "Frank Herbert"
omashelf read dune 30        # log 30 pages
omashelf page dune 168       # set the exact page
omashelf finish dune
omashelf list
omashelf stats
```

Put it on your `PATH` if you want it handy:

```bash
ln -s ~/.config/omarchy/plugins/io.github.daniel-felipe.omashelf/bin/omashelf ~/.local/bin/omashelf
```

## Settings

Configured per bar entry in `~/.config/omarchy/shell.json`, or through
Setup > Plugins.

| Key | Default | What it does |
|-----|---------|--------------|
| `barLabel` | `percent` | `percent`, `title`, `both`, or `icon` |
| `barTitleLimit` | `18` | Max title characters shown in the bar |
| `pageStep` | `10` | Pages moved by `]`/`[` and the `«` / `»` buttons |
| `libraryPath` | *(blank)* | Alternate library file |

```json
{ "id": "io.github.daniel-felipe.omashelf", "barLabel": "both", "pageStep": 25 }
```

## IPC

```bash
omarchy-shell omashelf toggle
omarchy-shell omashelf status     # "Dune — page 168/412 (41%) · ~2 days left"
omarchy-shell omashelf advance 20 # log 20 pages on the current book
```

## Library format

`~/.local/state/omarchy/omashelf/library.json`

```json
{
  "version": 1,
  "books": [
    {
      "id": "bk-...",
      "title": "Dune",
      "author": "Frank Herbert",
      "totalPages": 412,
      "currentPage": 168,
      "status": "reading",
      "started": "2026-08-01",
      "finished": "",
      "rating": 0,
      "log": [{ "date": "2026-08-23", "pages": 168 }]
    }
  ]
}
```

`status` is one of `reading`, `paused`, `finished`, `wishlist`. The `log`
entries are what the dashboard counts, so streaks and pace only reflect
progress you actually logged.

## Dependencies

- Omarchy shell (Quickshell) — the plugin host.
- A Nerd Font for the icons; Omarchy ships one by default.
- `python3` — only for the optional `bin/omashelf` CLI. The widget itself
  needs nothing beyond the shell.

## License

MIT — see [LICENSE](LICENSE).

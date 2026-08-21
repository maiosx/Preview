# Preview

Fuzzy-find any file and preview it instantly: images, syntax-highlighted code, PDFs, CSVs. Space pins the preview fullscreen; Enter opens it. The most-missed macOS feature, native to Omarchy.

Indexes `$HOME` by default (skips `.ssh`, `.gnupg`, password-store, keyrings, `node_modules`, `target`, `.git`, and other hidden directories). Preview cache is LRU-capped at 500 MB under `~/.cache/preview`. Selection history lives in `~/.local/state/preview/`. Nothing leaves the machine.

This is an Omarchy shell plugin (service + overlay + bar-widget). It runs inside the long-lived `omarchy-shell` process. It does not start a second Quickshell instance. The bar chip starts in `barWidget.defaultSection` (`right`). Click it to toggle the finder.

![Preview demo corpus — invoice, photo, table, Rust, README](demo.gif)

Five-file demo corpus the overlay shows before you type (invoice, photo, 5k-row CSV, themed Rust, README). Generated off-device from the shipped samples; a live Hyprland capture is not possible on the macOS authoring host.

## Install

```sh
omarchy plugin add https://github.com/maiosx/Preview.git --enable
```

That is the whole cold path. The installer does not run build hooks. On first summon the overlay talks to the **service-owned** helper over `omarchy-shell io.github.maiosx.preview` (Python `compat/` when the Rust binary is missing). Invoice PDF pages rasterize through resource-limited `pdftoppm` when Poppler is installed; images over 20 MP are downsampled before QML sees them. No `build.sh` is required to get a working finder.

The full Rust helper (`nucleo` ranking, sqlite frecency, isolated PDF children, 20 MP downsample) is optional. **This git tree does not and will not contain Linux prebuilts** — the authoring host is macOS, and fake binaries are worse than none.

1. Source build on the Omarchy box (the supported path when no release assets exist yet):

   ```sh
   ~/.config/omarchy/plugins/io.github.maiosx.preview/build.sh
   ```

2. After a tagged release, `.github/workflows/release.yml` cross-compiles musl `quicklookd` for `x86_64` and `aarch64` and publishes `CHECKSUMS.txt`. Fetch + verify:

   ```sh
   QUICKLOOK_RELEASE_REPO=<owner/repo> ~/.config/omarchy/plugins/io.github.maiosx.preview/scripts/fetch-helper.sh
   ```

Reload if the shell was already running:

```sh
omarchy-shell shell rescanPlugins
```

PDF previews need Poppler (`pdftoppm`):

```sh
pacman -S poppler
```

`fd` is the fast live search backend (preferred). `plocate` is a fallback:

```sh
pacman -S fd
# optional:
pacman -S plocate
sudo updatedb
```

## Usage

| Combo | Action |
|---|---|
| Bar chip | Toggle finder + preview |
| Super+. | Suggested toggle (add in bindings.lua) |
| Super+Alt+. | Alternate if Super+. is already taken |
| ↑ ↓ | Move selection (preview follows) |
| Space | Pin / unpin fullscreen preview |
| j / k | Next / previous PDF page when pinned |
| Enter | Open with `gio open` |
| Ctrl+Enter | Reveal parent folder |
| Esc | Unpin, then close |
| ? | Indexed roots, watch cap, cache use |

A hotkey is **opt-in**. Enabling the plugin does not write `~/.config/hypr/bindings.lua`. Add a bind yourself if you want one. Super+Shift+P is Omarchy's Google Photos bind and is never stolen. Super+Ctrl+. is Transcode and is not used.

Lua binds show dispatcher `__lua` plus a description — "ours" is plugin id in `arg` or description `Preview`.

```
bind = SUPER, period, exec, omarchy-shell shell toggle io.github.maiosx.preview '{}'
bind = SUPER ALT, period, exec, omarchy-shell shell toggle io.github.maiosx.preview '{}'
```

Summon a specific file from a terminal or file-manager custom action (the Wayland-honest stand-in for “Space in Finder”):

```sh
omarchy-shell shell summon io.github.maiosx.preview '{"path":"/abs/invoice.pdf"}'
# or, from this plugin dir:
bin/quicklook /abs/invoice.pdf
```

Before you type, the overlay shows a five-file demo corpus (invoice PDF, photo, 5k-row CSV, themed Rust, a README) so the first second is already useful while `$HOME` walks in the background.

## What renders in 1.0

| Format | How |
|---|---|
| Images (png/jpg/webp/svg/gif) | QML `Image` / `AnimatedImage`. Helper downsamples stills over 20 MP. |
| Code / text (~40 langs) | `syntect` → `<font color>` spans only (QML rich text has no CSS classes). Files over 200 KB are truncated and labeled “large file”. |
| PDF | `pdftoppm` in a disposable subprocess with CPU/memory rlimits and a wall-clock kill. No poppler → designed empty state. A failed render returns `render_error` + hex, never the raw PDF path (QML `Image` cannot display a PDF). Enter still opens. |
| CSV / TSV | First 500 rows as a zebra table; delimiter sniffing. |
| Directories | Entry listing + total size. |
| Anything else | Hex head + `file`-style magic. Never a blank pane. |

Video is **not** a player in 1.0. If `ffmpeg` is present the helper extracts a poster frame; otherwise the row shows metadata only.

## Settings

Settings are inline on the `shell.json` `plugins[]` entry. There is no separate config file for widget settings. The helper (Rust and the Python fallback) applies `roots`, `extraExclude`, `watchCap`, `cacheMb`, and `maxFiles` from a `config` command before indexing.

```json
{
  "id": "io.github.maiosx.preview",
  "roots": ["~/Documents", "~/Downloads", "~/Desktop"],
  "watchCap": 2000,
  "cacheMb": 500,
  "maxFiles": 500000
}
```

Omit `roots` to index `$HOME` (with the default exclude list). Watch coverage, cache use, poppler/plocate, and helper identity are visible from `?` in the overlay.

Power users who later want a denser inotify fan-out:

```sh
# documented, not required for 1.0 (we poll the top-N recent directories)
sysctl fs.inotify.max_user_watches
```

## IPC

`shell summon` / `hide` / `toggle` are host verbs for the overlay kind. Helper
verbs (`status`, `query`, `preview`, `snapshot`, `theme`, `prefetch`, `warmup`)
live on the **service `IpcHandler`**. `omarchy-shell shell call <id> <method>`
hits the overlay loader only — it does not reach the service. The supported
path is the plugin IpcHandler; always pass the string argument:

```sh
omarchy-shell shell toggle io.github.maiosx.preview '{}'
omarchy-shell shell summon io.github.maiosx.preview '{"path":"/tmp/file.pdf"}'
omarchy-shell shell hide io.github.maiosx.preview
omarchy-shell io.github.maiosx.preview status ''
omarchy-shell io.github.maiosx.preview query invo
omarchy-shell io.github.maiosx.preview preview '{"path":"/tmp/file.pdf","page":1}'
omarchy-shell io.github.maiosx.preview snapshot ''
omarchy-shell io.github.maiosx.preview theme '{"bg":"#1e1e2e","fg":"#cdd6f4","accent":"#89b4fa"}'
omarchy-shell io.github.maiosx.preview prefetch /tmp/file.pdf
omarchy-shell io.github.maiosx.preview warmup ''
omarchy-shell io.github.maiosx.preview installBinds ''
omarchy-shell io.github.maiosx.preview removeBinds ''
```

`preview` takes either a bare path or a `{"path":…,"page":N}` object. Overlay
root adapters (`query` / `preview` / `snapshot` / `status` / `theme` /
`prefetch` / `warmup`) forward to that same target (or `serviceFor` when the
host injects it).

The same IpcHandler is also reachable via `quickshell ipc`:

```sh
quickshell ipc -p "$OMARCHY_PATH/shell" call io.github.maiosx.preview ping ''
quickshell ipc -p "$OMARCHY_PATH/shell" call io.github.maiosx.preview preview '{"path":"/tmp/file.pdf"}'
```

Helper protocol (newline-delimited JSON on stdin/stdout, testable without the shell):

```sh
echo '{"q":"invo","id":41}' | bin/quicklookd --plugin-dir . --root ./samples
bin/quicklookd --oneshot '{"id":1,"cmd":"status"}'
```

## Honest limitations

- **Not macOS Quick Look on a file-manager selection.** Wayland does not expose the selected path of an arbitrary app. 1.0 is finder-first; `summon … '{"path":"…"}'` is the bridge.
- **Space is pin, not a search character.** Queries are path fragments without spaces.
- **Close is not a renderer for every format.** Markdown, archives, and video playback are v1.1. Hostile PDFs can only take down a `pdftoppm` child, never the shell.
- **Index cap 500k files**, watch/poll cap 2000 directories, preview cache 500 MB. Huge homes still get a cold path (`plocate` or a bounded walk) plus the demo corpus.
- **Frecency uses selection history + mtime, never atime** (relatime lies).
- **Helper binary.** `bin/quicklookd` is not in this git tree (see `bin/README.md` and `CHECKSUMS.txt`). Cold-judge `plugin add --enable` uses `compat/` (Python when present, POSIX `find` + real `gio open` otherwise). `build.sh` compiles from source. `.github/workflows/release.yml` is how Linux musl binaries and verified hashes are produced — they are not invented on macOS.
- **Keybinds are opt-in from the bar chip.** First load does not write `bindings.lua`. Occupied combos are skipped. Never `hl.unbind`. First open of the overlay repeats the table and the privacy sentence. The first-run card is persisted in `~/.local/state/preview/ui.json`.

## v1.1 roadmap

- Markdown rendering
- Archive listing
- Video playback polish (only if QtMultimedia *and* codecs exist on the shell build)

## Tests (off-device)

```sh
node tests/run.js
sh tests/protocol.test.sh
sh tests/compat-config.test.sh
cargo test --manifest-path src/quicklookd/Cargo.toml
```

## Remove

If you clicked **Set hotkey**, a marked `o.bind` block lives in `~/.config/hypr/bindings.lua`. Strip that block first, then remove the plugin:

```sh
python3 ~/.config/omarchy/plugins/io.github.maiosx.preview/compat/install-binds.py --remove io.github.maiosx.preview
omarchy plugin remove io.github.maiosx.preview
```

`Remove` on the bar chip does the same strip while the plugin is still installed. If the plugin directory is already gone, delete the marked block by hand:

```
-- BEGIN io.github.maiosx.preview
o.bind("SUPER + PERIOD", "Preview", "omarchy-shell shell toggle io.github.maiosx.preview '{}'")
-- END io.github.maiosx.preview
```

Hyprland reloads `bindings.lua` on save. The plugin never calls `hl.unbind`.

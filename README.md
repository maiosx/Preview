# Preview

Fuzzy-find any file and preview it instantly: images, syntax-highlighted code, PDFs, CSVs. Space pins the preview fullscreen; Enter opens it.

This is an Omarchy shell plugin (`overlay` + `service` + `bar-widget`).

## Install

```sh
omarchy plugin add https://github.com/maiosx/Preview.git --enable
```

Then reload if the shell is already running:

```sh
omarchy-shell shell rescanPlugins
```

Optional PDF previews:

```sh
pacman -S poppler
```

## Usage

| Combo | Action |
|---|---|
| Bar chip | Toggle finder + preview |
| Super+. | Suggested toggle (add in `bindings.lua`) |
| ↑ ↓ | Move selection |
| Space | Pin / unpin fullscreen preview |
| Enter | Open |
| Ctrl+Enter | Reveal parent folder |
| Esc | Unpin, then close |

```
bind = SUPER, period, exec, omarchy-shell shell toggle io.github.maiosx.preview '{}'
```

## Plugin id

`io.github.maiosx.preview`

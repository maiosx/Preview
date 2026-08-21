# Preview

Fuzzy-find any file and preview it instantly: images, syntax-highlighted code, PDFs, CSVs. Space pins the preview fullscreen; Enter opens it. The most-missed macOS feature, native to Omarchy.

## What it is

This is an Omarchy shell plugin (service + overlay + bar-widget). It runs inside the long-lived `omarchy-shell` process. It does not start a second Quickshell instance. The bar chip starts in `barWidget.defaultSection` (`right`). Click it to toggle the finder.

Install:

```sh
omarchy plugin add --enable https://github.com/maiosx/Preview
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

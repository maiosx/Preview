#!/usr/bin/env python3
import json, os, shutil, subprocess, sys
from pathlib import Path

HOME = Path(os.environ.get("HOME") or "/tmp")
SKIP = {".git", "node_modules", ".cache", "target", "__pycache__", ".ssh", ".gnupg", ".local"}

def parse_req():
    oneshot = None
    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == "--oneshot" and i + 1 < len(argv):
            oneshot = argv[i + 1]
            i += 2
        else:
            i += 1
    if oneshot:
        return json.loads(oneshot)
    line = sys.stdin.readline()
    return json.loads(line) if line.strip() else {"cmd": "status", "id": 0}

def kind_of(p: Path) -> str:
    if p.is_dir():
        return "dir"
    ext = p.suffix.lower().lstrip(".")
    if ext in {"png", "jpg", "jpeg", "webp", "gif", "svg", "bmp"}:
        return "image"
    if ext == "pdf":
        return "pdf"
    if ext in {"csv", "tsv"}:
        return "csv"
    if ext in {"rs", "js", "ts", "py", "go", "md", "qml", "json", "sh", "lua", "txt", "toml", "yml", "yaml"}:
        return "code"
    return "hex"

def score_name(name, q):
    n = name.lower()
    ql = (q or "").lower()
    if not ql:
        return 1
    if n == ql:
        return 1000
    if n.startswith(ql):
        return 800
    if ql in n:
        return 600
    return 200

def hits_from(paths, q, cap=40):
    out = []
    seen = set()
    for line in paths:
        raw = (line or "").strip().strip("'").strip('"')
        if not raw or raw in seen:
            continue
        p = Path(raw)
        if any(part in SKIP for part in p.parts):
            continue
        try:
            st = p.stat()
        except OSError:
            continue
        seen.add(raw)
        out.append({
            "path": str(p),
            "name": p.name,
            "kind": kind_of(p),
            "score": score_name(p.name, q),
            "mtime": int(st.st_mtime * 1000),
            "size": st.st_size,
        })
        if len(out) >= cap:
            break
    out.sort(key=lambda x: (-x["score"], x["name"]))
    return out

def run(cmd, timeout):
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, start_new_session=True)
        return [ln for ln in proc.stdout.splitlines() if ln.strip()]
    except Exception:
        return []

def search(q):
    q = (q or "").strip()
    if not q:
        return recent_files(), "recent"
    paths = []
    loc = shutil.which("plocate") or shutil.which("locate")
    if loc:
        paths = run([loc, "-i", "-l", "50", "-N", "--", q], 2)
        if not paths:
            paths = run([loc, "-i", "-l", "50", "--", q], 2)
    if not paths and shutil.which("fd"):
        paths = run(["fd", "-a", "-H", "-i", "--max-results", "50", q, str(HOME)], 3)
    if not paths and shutil.which("find"):
        roots = [HOME / d for d in ("Documents", "Downloads", "Desktop", "Pictures", "Videos", "Music", "Projects", "src", "code")]
        roots = [r for r in roots if r.is_dir()] or [HOME]
        for root in roots:
            chunk = run([
                "find", str(root), "-maxdepth", "6",
                "(", "-name", ".git", "-o", "-name", "node_modules", "-o", "-name", ".cache", ")",
                "-prune", "-o", "-iname", f"*{q}*", "-print",
            ], 3)
            paths.extend(chunk)
            if len(paths) >= 50:
                break
    return hits_from(paths, q), "compat"

def recent_files():
    roots = [HOME / d for d in ("Documents", "Downloads", "Desktop", "Pictures")]
    roots = [r for r in roots if r.is_dir()] or [HOME]
    paths = []
    if shutil.which("find"):
        for root in roots:
            paths.extend(run(["find", str(root), "-maxdepth", "2", "-type", "f"], 2))
    return hits_from(paths[:40], "")

def preview(path):
    p = Path(path)
    if not path:
        return {"kind": "hex", "label": "no file"}
    k = kind_of(p)
    if k == "image":
        return {"kind": "image", "path": str(p), "animated": p.suffix.lower() == ".gif"}
    return {"kind": k, "path": str(p), "label": k, "magic": k}

def handle(req):
    rid = int(req.get("id") or 0)
    cmd = req.get("cmd") or ("query" if "q" in req else "status")
    if cmd == "query":
        hits, backend = search(str(req.get("q") or ""))
        return {"id": rid, "kind": "results", "results": hits, "indexing": False, "progress": 1.0, "backend": backend}
    if cmd in ("preview", "prefetch", "page"):
        return {"id": rid, "kind": "preview", "preview": preview(str(req.get("path") or ""))}
    return {"id": rid, "kind": "status", "status": {"helper": "compat"}, "backend": "compat"}

def main():
    print(json.dumps(handle(parse_req())), flush=True)

if __name__ == "__main__":
    main()

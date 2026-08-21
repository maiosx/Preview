#!/usr/bin/env python3
import json, os, shutil, subprocess, sys
from pathlib import Path

HOME = Path(os.environ.get("HOME") or "/tmp")
SKIP = {".git", "node_modules", ".cache", "target", "__pycache__", ".ssh", ".gnupg"}

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
    ext = p.suffix.lower().lstrip(".")
    if ext in {"png", "jpg", "jpeg", "webp", "gif", "svg"}:
        return "image"
    if ext == "pdf":
        return "pdf"
    if ext in {"csv", "tsv"}:
        return "csv"
    if ext in {"rs", "js", "ts", "py", "go", "md", "qml", "json", "sh", "lua", "txt"}:
        return "code"
    return "hex" if p.is_file() else "dir"

def hits_from(paths, q, cap=40):
    out = []
    ql = q.lower()
    for line in paths:
        p = Path(line.strip())
        if not line.strip():
            continue
        if any(part in SKIP for part in p.parts):
            continue
        try:
            st = p.stat()
        except OSError:
            continue
        name = p.name
        score = 800 if name.lower().startswith(ql) else 600 if ql in name.lower() else 200
        out.append({
            "path": str(p),
            "name": name,
            "kind": kind_of(p),
            "score": score,
            "mtime": int(st.st_mtime * 1000),
            "size": st.st_size,
        })
        if len(out) >= cap:
            break
    out.sort(key=lambda x: (-x["score"], x["name"]))
    return out

def search(q: str):
    q = "".join(ch for ch in q if ch.isalnum() or ch in ".._-")
    if not q:
        return [], "compat"
    loc = shutil.which("plocate") or shutil.which("locate")
    paths = []
    if loc:
        try:
            proc = subprocess.run([loc, "-il", "40", "--", q], capture_output=True, text=True, timeout=2)
            paths = proc.stdout.splitlines()
        except Exception:
            paths = []
    if not paths and shutil.which("find"):
        try:
            proc = subprocess.run(
                ["find", str(HOME), "-iname", f"*{q}*",
                 "(", "-name", ".git", "-o", "-name", "node_modules", "-o", "-name", ".cache", ")",
                 "-prune", "-o", "-print"],
                capture_output=True, text=True, timeout=4,
            )
            paths = proc.stdout.splitlines()[:80]
        except Exception:
            paths = []
    return hits_from(paths, q), "compat"

def preview(path: str):
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
    return {"id": rid, "kind": "status", "status": {"helper": "compat", "plocate": bool(shutil.which("plocate"))}, "backend": "compat"}

def main():
    req = parse_req()
    print(json.dumps(handle(req)), flush=True)

if __name__ == "__main__":
    main()

.pragma library

function defaultSamples(pluginDir) {
  var root = String(pluginDir || "")
  if (root.length && root.charAt(root.length - 1) === "/")
    root = root.slice(0, root.length - 1)
  var base = root + "/samples"
  return [
    { path: base + "/invoice.pdf", name: "invoice.pdf", kind: "pdf", score: 900, mtime: 0, size: 0 },
    { path: base + "/photo.png", name: "photo.png", kind: "image", score: 880, mtime: 0, size: 0 },
    { path: base + "/sales.csv", name: "sales.csv", kind: "csv", score: 860, mtime: 0, size: 0 },
    { path: base + "/themed.rs", name: "themed.rs", kind: "code", score: 840, mtime: 0, size: 0 },
    { path: base + "/README.md", name: "README.md", kind: "code", score: 820, mtime: 0, size: 0 }
  ]
}

function fuzzyScore(hay, needle) {
  var h = String(hay || "").toLowerCase()
  var n = String(needle || "").toLowerCase()
  if (!n.length) return 1
  var idx = h.indexOf(n)
  if (idx === 0) return 800
  if (idx > 0) return 600 - idx
  return 0
}

function search(items, query, limit) {
  var q = String(query || "")
  var cap = Number(limit) || 40
  var src = items || []
  if (!q.length) return src.slice(0, cap)
  var scored = []
  for (var i = 0; i < src.length; i++) {
    var it = src[i]
    var s = Math.max(fuzzyScore(it.name, q), fuzzyScore(it.path, q))
    if (s <= 0) continue
    scored.push({ path: it.path, name: it.name, kind: it.kind || "hex", score: s, mtime: 0, size: 0 })
  }
  scored.sort(function(a, b) { return b.score - a.score })
  return scored.slice(0, cap)
}

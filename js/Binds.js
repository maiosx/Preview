.pragma library

var PLUGIN_ID = "io.github.maiosx.preview"
var offer = { needed: true, note: "", installed: 0, hotkeyLabel: "", canSet: false, toAdd: [], skipped: [] }
function setOffer(next) { offer = next || offer }
function applyScan(raw) { return offer }
function notifyBody() { return "" }
function notifyArgv(appName, headline, body) {
  return ["omarchy", "notification", "send", "--app-name", String(appName || PLUGIN_ID), String(headline || ""), String(body || "")]
}
function luaBlock() { return "" }

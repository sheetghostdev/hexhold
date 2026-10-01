class_name NetPeer
extends Node
## A direct browser-to-browser connection (WebRTC through PeerJS). The host
## player's browser runs the match; the guest connects to it with the code
## from the invite link. Messages are JSON dictionaries.
##
## Swap this class for a relay-server transport later without touching the
## game: it only needs host(), join(), send() and the signals below.

signal ready_to_host
signal opened
signal closed
signal received(msg: Dictionary)
signal failed(reason: String)

const PREFIX := "hexhold-mil-"

const GLUE := """
window.hexNet = window.hexNet || (function() {
	var inbox = [], peer = null, conn = null;
	var q = new URLSearchParams(location.search);
	var debug = q.has('debug');
	function push(o) { inbox.push(o); }
	function load(cb) {
		if (window.Peer) { cb(); return; }
		var s = document.createElement('script');
		s.src = (debug && q.get('peerlib')) || 'https://cdn.jsdelivr.net/npm/peerjs@1.5.4/dist/peerjs.min.js';
		s.onload = cb;
		s.onerror = function() { push({ k: 'error', msg: 'network-library' }); };
		document.head.appendChild(s);
	}
	function opts() {
		var o = { debug: 1 };
		if (debug && q.get('peerhost')) {
			o.host = q.get('peerhost'); o.port = Number(q.get('peerport') || 9000);
			o.path = '/'; o.secure = false;
		}
		return o;
	}
	function wire(c) {
		conn = c;
		c.on('open', function() { push({ k: 'open' }); });
		c.on('data', function(d) { push({ k: 'data', d: d }); });
		c.on('close', function() { if (conn === c) { conn = null; push({ k: 'close' }); } });
		c.on('error', function(e) { push({ k: 'error', msg: String(e && e.type || e) }); });
	}
	return {
		host: function(id) { load(function() {
			peer = new Peer(id, opts());
			peer.on('open', function() { push({ k: 'ready' }); });
			peer.on('connection', function(c) {
				var old = conn; wire(c);
				if (old) { try { old.close(); } catch (e) {} }
			});
			peer.on('error', function(e) { push({ k: 'error', msg: String(e && e.type || e) }); });
			peer.on('disconnected', function() { try { peer.reconnect(); } catch (e) {} });
		}); },
		join: function(id) { load(function() {
			peer = new Peer(opts());
			peer.on('open', function() { wire(peer.connect(id, { reliable: true })); });
			peer.on('error', function(e) { push({ k: 'error', msg: String(e && e.type || e) }); });
		}); },
		send: function(s) { if (conn && conn.open) { conn.send(s); return true; } return false; },
		poll: function() { var o = JSON.stringify(inbox); inbox = []; return o; },
		close: function() {
			try { if (conn) conn.close(); if (peer) peer.destroy(); } catch (e) {}
			conn = null; peer = null; inbox = [];
		}
	};
})();
"""

var is_open := false


func _ready() -> void:
	if Net.is_web():
		JavaScriptBridge.eval(GLUE, true)


static func new_code() -> String:
	const ALPHA := "abcdefghjkmnpqrstuvwxyz23456789"
	var s := ""
	for i in 6:
		s += ALPHA[randi() % ALPHA.length()]
	return s


func host(code: String) -> void:
	if Net.is_web():
		JavaScriptBridge.eval("window.hexNet.host(%s)" % JSON.stringify(PREFIX + code), true)


func join(code: String) -> void:
	if Net.is_web():
		JavaScriptBridge.eval("window.hexNet.join(%s)" % JSON.stringify(PREFIX + code), true)


func send(msg: Dictionary) -> bool:
	if not Net.is_web():
		return false
	return Net._truthy(JavaScriptBridge.eval("window.hexNet.send(%s)" % JSON.stringify(JSON.stringify(msg)), true))


func close() -> void:
	if Net.is_web():
		JavaScriptBridge.eval("window.hexNet && window.hexNet.close()", true)
	is_open = false


func _exit_tree() -> void:
	close()


func _process(_delta: float) -> void:
	if not Net.is_web():
		return
	var raw = JavaScriptBridge.eval("window.hexNet ? window.hexNet.poll() : '[]'", true)
	if not raw is String or raw == "[]":
		return
	var items = JSON.parse_string(raw)
	if not items is Array:
		return
	for it in items:
		match it.get("k", ""):
			"ready":
				ready_to_host.emit()
			"open":
				is_open = true
				opened.emit()
			"close":
				is_open = false
				closed.emit()
			"error":
				failed.emit(String(it.get("msg", "error")))
			"data":
				var msg = JSON.parse_string(String(it.get("d", "")))
				if msg is Dictionary:
					received.emit(msg)

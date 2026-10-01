class_name Net
extends RefCounted
## Browser glue: reading the turn from the link, sharing a turn to
## Discord (via the phone's share sheet), clipboard and text prompts.

static func is_web() -> bool:
	return OS.has_feature("web")


## The turn code carried in the page address (#g=...), or "".
static func code_from_location() -> String:
	if not is_web():
		return ""
	var h = JavaScriptBridge.eval("window.location.hash || ''", true)
	if typeof(h) != TYPE_STRING or h == "":
		return ""
	return Codec.extract_code(h)


static func clear_location_code() -> void:
	if is_web():
		JavaScriptBridge.eval("history.replaceState(null, '', window.location.pathname + window.location.search)", true)


## Address that links should point at.
static func base_url() -> String:
	if is_web():
		var u = JavaScriptBridge.eval("window.location.origin + window.location.pathname", true)
		if typeof(u) == TYPE_STRING and u.begins_with("http"):
			return u
	return Storage.get_setting("base_url", "")


static func turn_link(code: String) -> String:
	var base := base_url()
	if base == "":
		return "HEXHOLD:" + code
	return base + "#g=" + code


## Opens the share sheet (Discord, Messages...). Falls back to the clipboard.
## Returns true if the share sheet was used.
static func share(title: String, text: String) -> bool:
	if is_web():
		var js := """
		(function(t, x) {
			if (navigator.share) {
				navigator.share({ title: t, text: x }).catch(function(e) {});
				return true;
			}
			if (navigator.clipboard) { navigator.clipboard.writeText(x).catch(function(e) {}); }
			return false;
		})(%s, %s)
		""" % [JSON.stringify(title), JSON.stringify(text)]
		var r = JavaScriptBridge.eval(js, true)
		return r == true
	copy(text)
	return false


static func can_share_sheet() -> bool:
	if not is_web():
		return false
	return JavaScriptBridge.eval("!!navigator.share", true) == true


static func copy(text: String) -> void:
	if is_web():
		JavaScriptBridge.eval("navigator.clipboard && navigator.clipboard.writeText(%s).catch(function(e){})" % JSON.stringify(text), true)
	DisplayServer.clipboard_set(text)


## Synchronous native text prompt on the web (reliable on phones,
## supports paste). Returns null when unavailable or cancelled.
static func prompt(message: String, default: String = "") -> Variant:
	if not is_web():
		return null
	var r = JavaScriptBridge.eval("prompt(%s, %s)" % [JSON.stringify(message), JSON.stringify(default)], true)
	if typeof(r) != TYPE_STRING:
		return ""
	return r


static func vibrate(ms: int = 15) -> void:
	if is_web():
		JavaScriptBridge.eval("navigator.vibrate && navigator.vibrate(%d)" % ms, true)
	elif OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)

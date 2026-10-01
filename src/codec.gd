class_name Codec
extends RefCounted
## Packs a GameState into a compact binary blob, deflates it and turns it
## into URL-safe text. A whole game fits in a link short enough for Discord.

const MAGIC := 0x48  # 'H'


static func encode(gs: GameState) -> String:
	var raw := encode_bytes(gs)
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var out := PackedByteArray([MAGIC, raw.size() & 0xff, (raw.size() >> 8) & 0xff, (raw.size() >> 16) & 0xff])
	out.append_array(packed)
	return Marshalls.raw_to_base64(out).replace("+", "-").replace("/", "_").replace("=", "")


static func decode(text: String) -> GameState:
	var code := extract_code(text)
	if code.is_empty():
		return null
	var b64 := code.replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var data := Marshalls.base64_to_raw(b64)
	if data.size() < 5 or data[0] != MAGIC:
		return null
	var size := data[1] | (data[2] << 8) | (data[3] << 16)
	if size <= 0 or size > 1 << 20:
		return null
	var raw := data.slice(4).decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != size:
		return null
	return decode_bytes(raw)


## Accepts a full link ("https://.../#g=CODE"), "g=CODE" or the bare code.
static func extract_code(text: String) -> String:
	var t := text.strip_edges()
	var k := t.find("g=")
	if k >= 0:
		t = t.substr(k + 2)
	var end := t.length()
	for sep in ["&", " ", "\n", "\t", ">", ")"]:
		var j := t.find(sep)
		if j >= 0:
			end = mini(end, j)
	t = t.substr(0, end)
	var ok := RegEx.create_from_string("^[A-Za-z0-9_-]+$")
	if ok.search(t) == null:
		return ""
	return t


# ---------------------------------------------------------------- binary

static func encode_bytes(gs: GameState) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(GameState.VERSION)
	_put_str(b, gs.game_id)
	b.put_u32(gs.map_seed & 0xffffffff)
	b.put_u8(gs.w)
	b.put_u8(gs.h)
	b.put_u16(gs.turn)
	b.put_u8(gs.cur)
	b.put_u8(gs.mode)
	b.put_u8(gs.turn_limit)
	b.put_u8(1 if gs.online else 0)
	b.put_8(gs.winner)
	b.put_u32(gs.seq)
	var n := gs.n_tiles()
	b.put_u8(gs.players.size())
	for p in gs.players:
		_put_str(b, p.name)
		b.put_u8(p.color)
		b.put_u16(clampi(p.gold, 0, 65535))
		b.put_u16(clampi(p.wood, 0, 65535))
		b.put_u16(clampi(p.stone, 0, 65535))
		b.put_u8(p.keep)
		b.put_u8(p.tax)
		b.put_u8((1 if p.ai else 0) | (2 if p.alive else 0))
		b.put_u32(p.seen_seq)
		b.put_u16(p.kills)
		b.put_data(_bits(p.explored, n))
	var tiles := PackedByteArray()
	tiles.resize(n * 3)
	var hps := PackedByteArray()
	for i in n:
		tiles[i] = gs.terrain[i] | (gs.feature[i] << 3)
		tiles[n + i] = gs.building[i] | (gs.road[i] << 4)
		tiles[2 * n + i] = gs.claim[i]
		if gs.building[i] == Defs.B.WALL or gs.building[i] == Defs.B.TOWER:
			hps.append(gs.bhp[i])
	b.put_data(tiles)
	b.put_data(hps)
	b.put_u8(gs.towns.size())
	for t in gs.towns:
		b.put_u16(t.idx)
		b.put_8(t.owner)
		b.put_u8(t.level)
		b.put_u8(t.food)
		b.put_u8((1 if t.walls else 0) | (2 if t.capital else 0) | (4 if t.feasted else 0))
		var ni := Defs.TOWN_NAMES.find(t.name)
		b.put_u8(ni if ni >= 0 else 255)
		if ni < 0:
			_put_str(b, t.name)
	b.put_u16(gs.units.size())
	for u in gs.units:
		b.put_u16(u.idx)
		b.put_u8(u.type | (1 << 3 if u.moved else 0) | (1 << 4 if u.attacked else 0) | (1 << 5 if u.fresh else 0))
		b.put_u8((u.owner + 1) | (mini(u.kills, 15) << 4))
		b.put_u8(clampi(u.hp, 0, 255))
	b.put_u8(gs.events.size())
	for e in gs.events:
		b.put_u16(clampi(gs.seq - int(e[0]), 0, 65535))
		b.put_u16(e[1])
		b.put_u8(e[2])
		b.put_u8(e.size() - 3)
		for k in range(3, e.size()):
			b.put_16(clampi(int(e[k]), -32768, 32767))
	return b.data_array


static func decode_bytes(data: PackedByteArray) -> GameState:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var gs := GameState.new()
	var ver := b.get_u8()
	if ver != GameState.VERSION:
		push_warning("Unknown save version %d" % ver)
		return null
	gs.game_id = _get_str(b)
	gs.map_seed = b.get_u32()
	gs.w = b.get_u8()
	gs.h = b.get_u8()
	gs.turn = b.get_u16()
	gs.cur = b.get_u8()
	gs.mode = b.get_u8()
	gs.turn_limit = b.get_u8()
	gs.online = b.get_u8() == 1
	gs.winner = b.get_8()
	gs.seq = b.get_u32()
	var n := gs.n_tiles()
	if n <= 0 or n > 4096:
		return null
	var np := b.get_u8()
	for i in np:
		var p := GameState.Player.new()
		p.name = _get_str(b)
		p.color = b.get_u8()
		p.gold = b.get_u16()
		p.wood = b.get_u16()
		p.stone = b.get_u16()
		p.keep = b.get_u8()
		p.tax = b.get_u8()
		var fl := b.get_u8()
		p.ai = fl & 1 != 0
		p.alive = fl & 2 != 0
		p.seen_seq = b.get_u32()
		p.kills = b.get_u16()
		p.explored = _unbits(_get_raw(b, (n + 7) / 8), n)
		gs.players.append(p)
	var tiles := _get_raw(b, n * 3)
	if tiles.size() != n * 3:
		return null
	gs.terrain.resize(n)
	gs.feature.resize(n)
	gs.building.resize(n)
	gs.bhp.resize(n)
	gs.road.resize(n)
	gs.claim.resize(n)
	var structures: Array[int] = []
	for i in n:
		gs.terrain[i] = tiles[i] & 7
		gs.feature[i] = tiles[i] >> 3
		gs.building[i] = tiles[n + i] & 15
		gs.road[i] = (tiles[n + i] >> 4) & 1
		gs.claim[i] = tiles[2 * n + i]
		gs.bhp[i] = 0
		if gs.building[i] == Defs.B.WALL or gs.building[i] == Defs.B.TOWER:
			structures.append(i)
	var hps := _get_raw(b, structures.size())
	for k in structures.size():
		gs.bhp[structures[k]] = hps[k]
	var nt := b.get_u8()
	for i in nt:
		var t := GameState.Town.new()
		t.idx = b.get_u16()
		t.owner = b.get_8()
		t.level = b.get_u8()
		t.food = b.get_u8()
		var fl := b.get_u8()
		t.walls = fl & 1 != 0
		t.capital = fl & 2 != 0
		t.feasted = fl & 4 != 0
		var ni := b.get_u8()
		t.name = _get_str(b) if ni == 255 else Defs.TOWN_NAMES[mini(ni, Defs.TOWN_NAMES.size() - 1)]
		gs.towns.append(t)
	var nu := b.get_u16()
	for i in nu:
		var u := GameState.Unit.new()
		u.id = i + 1
		u.idx = b.get_u16()
		var fl := b.get_u8()
		u.type = fl & 7
		u.moved = fl & 8 != 0
		u.attacked = fl & 16 != 0
		u.fresh = fl & 32 != 0
		var ok := b.get_u8()
		u.owner = (ok & 15) - 1
		u.kills = ok >> 4
		u.hp = b.get_u8()
		gs.units.append(u)
	gs.next_unit_id = nu + 1
	var ne := b.get_u8()
	for i in ne:
		var e := [gs.seq - b.get_u16(), b.get_u16(), b.get_u8()]
		var na := b.get_u8()
		for k in na:
			e.append(b.get_16())
		gs.events.append(e)
	if b.get_position() > data.size():
		return null
	gs.rebuild_caches()
	return gs


static func _put_str(b: StreamPeerBuffer, s: String) -> void:
	var bytes := s.to_utf8_buffer()
	if bytes.size() > 255:
		bytes = bytes.slice(0, 255)
	b.put_u8(bytes.size())
	b.put_data(bytes)


static func _get_str(b: StreamPeerBuffer) -> String:
	var len := b.get_u8()
	return _get_raw(b, len).get_string_from_utf8()


static func _get_raw(b: StreamPeerBuffer, size: int) -> PackedByteArray:
	if size <= 0:
		return PackedByteArray()
	var r: Array = b.get_data(size)
	if r[0] != OK:
		return PackedByteArray()
	return r[1]


static func _bits(arr: PackedByteArray, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize((n + 7) / 8)
	for i in n:
		if i < arr.size() and arr[i] != 0:
			out[i >> 3] |= 1 << (i & 7)
	return out


static func _unbits(bits: PackedByteArray, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	for i in n:
		if (i >> 3) < bits.size() and bits[i >> 3] & (1 << (i & 7)):
			out[i] = 1
	return out

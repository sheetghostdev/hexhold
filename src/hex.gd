class_name Hex
extends RefCounted
## Pointy-top hex math. The map is stored in "odd-r" offset coordinates
## (col, row); gameplay math uses axial (q, r).

const SIZE := 52.0  # center-to-corner radius in world pixels
const SQRT3 := 1.7320508075688772

const AXIAL_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - (row - (row & 1)) / 2, row)


static func axial_to_offset(a: Vector2i) -> Vector2i:
	return Vector2i(a.x + (a.y - (a.y & 1)) / 2, a.y)


static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


static func offset_to_pixel(col: int, row: int) -> Vector2:
	return Vector2(SIZE * SQRT3 * (col + 0.5 * (row & 1)), SIZE * 1.5 * row)


static func pixel_to_offset(p: Vector2) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / SIZE
	var r := (2.0 / 3.0 * p.y) / SIZE
	return axial_to_offset(axial_round(q, r))


static func axial_round(fq: float, fr: float) -> Vector2i:
	var fs := -fq - fr
	var q := roundf(fq)
	var r := roundf(fr)
	var s := roundf(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


static func corners(center: Vector2, size: float = SIZE) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * size)
	return pts


## Axial line between two hexes (inclusive), used for drag-painting roads.
static func axial_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := axial_distance(a, b)
	var out: Array[Vector2i] = []
	for i in n + 1:
		var t := 0.0 if n == 0 else float(i) / n
		var fq := lerpf(a.x + 1e-6, b.x + 1e-6, t)
		var fr := lerpf(a.y + 1e-6, b.y + 1e-6, t)
		out.append(axial_round(fq, fr))
	return out

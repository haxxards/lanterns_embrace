class_name Hex
extends RefCounted
## Pointy-top hexagon math on axial coordinates (q, r), stored as Vector2i.
##
## Axial coordinates keep distance, neighbour and range math simple. Map text
## files use "odd-r" offset coordinates (col, row) because they read naturally
## as rows of characters; convert with offset_to_axial() / axial_to_offset().
## Reference: https://www.redblobgames.com/grids/hexagons/

const SQRT3 := 1.7320508075688772

## Neighbour offsets, counter-clockwise starting east:
## E, NE, NW, W, SW, SE.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Which DIRECTIONS entry the edge between corner i and corner i+1 faces.
const EDGE_DIRECTION: Array[int] = [0, 5, 4, 3, 2, 1]


static func neighbor(h: Vector2i, direction: int) -> Vector2i:
	return h + DIRECTIONS[posmod(direction, 6)]


static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(h + d)
	return out


@warning_ignore("integer_division")
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


## Centre of hex `h` in world pixels, for a hex of the given corner radius.
static func to_pixel(h: Vector2i, radius: float) -> Vector2:
	return Vector2(radius * SQRT3 * (h.x + h.y * 0.5), radius * 1.5 * h.y)


## Hex containing world pixel `p`.
static func from_pixel(p: Vector2, radius: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / radius
	var r := (2.0 / 3.0 * p.y) / radius
	return axial_round(q, r)


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


## Odd-r offset (col, row) -> axial (q, r). Odd rows sit half a hex to the right.
@warning_ignore("integer_division")
static func offset_to_axial(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x - (cell.y - (cell.y & 1)) / 2, cell.y)


## Axial (q, r) -> odd-r offset (col, row).
@warning_ignore("integer_division")
static func axial_to_offset(h: Vector2i) -> Vector2i:
	return Vector2i(h.x + (h.y - (h.y & 1)) / 2, h.y)


## The six corner points of a hex centred at `center`, clockwise from upper-right.
static func corners(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


## Hexes exactly `radius` steps from `center`.
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius <= 0:
		out.append(center)
		return out
	var h := center + DIRECTIONS[4] * radius
	for side in 6:
		for _step in radius:
			out.append(h)
			h = neighbor(h, side)
	return out


## All hexes within `radius` of `center`, nearest rings first.
static func spiral(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in radius + 1:
		out.append_array(ring(center, k))
	return out


## Hexes on the straight line from a to b (inclusive). Used for line of sight.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var out: Array[Vector2i] = []
	if n == 0:
		out.append(a)
		return out
	# Nudge so ties between two hexes resolve consistently.
	var aq := a.x + 1e-6
	var ar := a.y + 2e-6
	for i in n + 1:
		var t := float(i) / n
		out.append(axial_round(lerpf(aq, b.x, t), lerpf(ar, b.y, t)))
	return out

extends TestCase


func test_distance() -> void:
	check_eq(Hex.distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "same hex")
	check_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, -1)), 3, "(0,0)->(3,-1)")
	check_eq(Hex.distance(Vector2i(-2, 4), Vector2i(1, 1)), 3, "(-2,4)->(1,1)")
	check_eq(Hex.distance(Vector2i(5, 2), Vector2i(-1, 3)), Hex.distance(Vector2i(-1, 3), Vector2i(5, 2)), "symmetric")


func test_neighbors_are_adjacent_and_unique() -> void:
	var c := Vector2i(4, -3)
	var ns := Hex.neighbors(c)
	check_eq(ns.size(), 6, "six neighbours")
	var seen := {}
	for n in ns:
		check_eq(Hex.distance(c, n), 1, "neighbour %s distance" % n)
		seen[n] = true
	check_eq(seen.size(), 6, "neighbours unique")


func test_offset_round_trip() -> void:
	for row in range(-5, 6):
		for col in range(-5, 6):
			var cell := Vector2i(col, row)
			check_eq(Hex.axial_to_offset(Hex.offset_to_axial(cell)), cell, "round trip %s" % cell)


func test_offset_rows_are_odd_r() -> void:
	# Odd rows sit half a hex to the right of the even row above them.
	var r := 32.0
	var even := Hex.to_pixel(Hex.offset_to_axial(Vector2i(3, 0)), r)
	var odd := Hex.to_pixel(Hex.offset_to_axial(Vector2i(3, 1)), r)
	check(is_equal_approx(odd.x - even.x, Hex.SQRT3 * r * 0.5), "odd row shifted right by half a hex")


func test_pixel_round_trip() -> void:
	var r := 32.0
	for q in range(-6, 7):
		for rr in range(-6, 7):
			var h := Vector2i(q, rr)
			var p := Hex.to_pixel(h, r)
			check_eq(Hex.from_pixel(p, r), h, "centre of %s" % h)
			for a in 6:
				var off := Vector2.from_angle(a * TAU / 6.0 + 0.3) * r * 0.75
				check_eq(Hex.from_pixel(p + off, r), h, "inside %s" % h)


func test_ring_and_spiral_sizes() -> void:
	check_eq(Hex.ring(Vector2i.ZERO, 0).size(), 1, "ring 0")
	check_eq(Hex.ring(Vector2i(2, 1), 2).size(), 12, "ring 2")
	check_eq(Hex.spiral(Vector2i(2, 1), 2).size(), 19, "spiral 2")
	for h in Hex.ring(Vector2i(2, 1), 3):
		check_eq(Hex.distance(Vector2i(2, 1), h), 3, "ring 3 member %s" % h)


func test_line_is_contiguous() -> void:
	var a := Vector2i(-3, 2)
	var b := Vector2i(4, -2)
	var line := Hex.line(a, b)
	check_eq(line.size(), Hex.distance(a, b) + 1, "line length")
	check_eq(line[0], a, "line start")
	check_eq(line[-1], b, "line end")
	for i in range(1, line.size()):
		check_eq(Hex.distance(line[i - 1], line[i]), 1, "step %d" % i)


func test_edge_direction_matches_corners() -> void:
	# The edge between corner e and e+1 must face neighbour EDGE_DIRECTION[e].
	var r := 32.0
	var h := Vector2i(1, 2)
	var pts := Hex.corners(Hex.to_pixel(h, r), r)
	for e in 6:
		var mid := (pts[e] + pts[(e + 1) % 6]) * 0.5
		var other := Hex.neighbor(h, Hex.EDGE_DIRECTION[e])
		var d1 := mid.distance_to(Hex.to_pixel(h, r))
		var d2 := mid.distance_to(Hex.to_pixel(other, r))
		check(is_equal_approx(d1, d2), "edge %d faces direction %d" % [e, Hex.EDGE_DIRECTION[e]])

class_name TerrainRenderer
extends Node2D
## Draws the map's ground as one seamless surface (see terrain_blend.gdshader).
##
## The hex grid still decides what terrain each hex *is* (walkable, cost...),
## but the ground is painted from weight maps baked from that grid, with a
## noisy domain warp, so rivers, roads and fields meet along natural edges
## instead of hex outlines. Terrain textures are sampled in world space, so
## any seamless texture can be dropped in.

const SHADER := preload("res://scripts/world/terrain_blend.gdshader")
const MAX_SLOTS := 12
## Terrain textures are resampled to this size; 1 texel = 1 world pixel.
const TEXTURE_SIZE := 512

var bounds := Rect2()
## Terrains that share a texture share a slot (e.g. bridge deck over water).
var slot_of_texture: Dictionary = {}  # texture path -> slot index
var slot_textures: Array[Texture2D] = []
var splat_textures: Array[ImageTexture] = []

var _slot_of_terrain: Dictionary = {}  # TerrainDef -> slot index


func build(grid: HexGrid) -> void:
	bounds = grid.world_bounds()
	_assign_slots(grid)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("terrain_textures", _build_texture_array())
	mat.set_shader_parameter("slot_count", slot_textures.size())
	mat.set_shader_parameter("animated_mask", _animated_mask())
	mat.set_shader_parameter("noise", _noise_texture())
	mat.set_shader_parameter("texture_world_size", float(TEXTURE_SIZE))
	mat.set_shader_parameter("edge_noise", GameConfig.terrain_edge_noise)
	mat.set_shader_parameter("edge_sharpness", GameConfig.terrain_edge_sharpness)
	var px := GameConfig.terrain_splat_px
	var splat_cells := _bake_splats(grid, px)
	for i in 3:
		mat.set_shader_parameter("splat_%d" % i, splat_textures[i])
	mat.set_shader_parameter("splat_origin", bounds.position)
	mat.set_shader_parameter("splat_size", Vector2(splat_cells) * px)
	material = mat
	queue_redraw()


func _draw() -> void:
	if bounds.has_area():
		draw_rect(bounds, Color.WHITE)


func _assign_slots(grid: HexGrid) -> void:
	slot_of_texture.clear()
	slot_textures.clear()
	_slot_of_terrain.clear()
	for i in grid.cell_count():
		var t := grid.get_terrain(grid.hex_at_index(i))
		if t == null or _slot_of_terrain.has(t):
			continue
		var key := t.texture_path if not t.texture_path.is_empty() else "terrain:" + t.id
		if not slot_of_texture.has(key):
			if slot_textures.size() >= MAX_SLOTS:
				push_warning("Map uses more than %d terrain textures; '%s' drawn as slot 0" % [MAX_SLOTS, t.id])
				_slot_of_terrain[t] = 0
				continue
			slot_of_texture[key] = slot_textures.size()
			slot_textures.append(t.texture)
		_slot_of_terrain[t] = slot_of_texture[key]
	if slot_textures.is_empty():
		slot_textures.append(Data.missing_texture())


## Bit mask of slots whose terrain is animated (water).
func _animated_mask() -> int:
	var mask := 0
	for t: TerrainDef in _slot_of_terrain:
		if t.animated:
			mask |= 1 << int(_slot_of_terrain[t])
	return mask


## Packs every terrain texture into one array (same size, RGBA8, mipmapped).
func _build_texture_array() -> Texture2DArray:
	var images: Array[Image] = []
	for tex in slot_textures:
		var img: Image = tex.get_image() if tex else null
		if img == null:
			img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != TEXTURE_SIZE or img.get_height() != TEXTURE_SIZE:
			img.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		images.append(img)
	var arr := Texture2DArray.new()
	var err := arr.create_from_images(images)
	if err != OK:
		push_error("TerrainRenderer: could not build texture array (%s)" % error_string(err))
	return arr


## Bakes terrain weights: one texel every `px` world pixels, each texel fully
## weighted to the terrain of the (noise-warped) hex it falls in. Bilinear
## filtering in the shader turns these into soft, organic transitions.
func _bake_splats(grid: HexGrid, px: float) -> Vector2i:
	var sw := int(ceil(bounds.size.x / px)) + 1
	var sh := int(ceil(bounds.size.y / px)) + 1
	# Three local arrays (not an Array of them) so writes stay in place.
	var d0 := PackedByteArray()
	var d1 := PackedByteArray()
	var d2 := PackedByteArray()
	d0.resize(sw * sh * 4)
	d1.resize(sw * sh * 4)
	d2.resize(sw * sh * 4)
	d0.fill(0)
	d1.fill(0)
	d2.fill(0)
	var warp_x := FastNoiseLite.new()
	warp_x.seed = 1337
	warp_x.frequency = 1.0 / (grid.radius * 2.5)
	var warp_y := FastNoiseLite.new()
	warp_y.seed = 7331
	warp_y.frequency = warp_x.frequency
	var amp := grid.radius * GameConfig.terrain_warp
	for y in sh:
		for x in sw:
			var p := bounds.position + Vector2(x + 0.5, y + 0.5) * px
			p += Vector2(warp_x.get_noise_2d(p.x, p.y), warp_y.get_noise_2d(p.x, p.y)) * amp
			var slot := _slot_at(grid, p)
			var idx := (y * sw + x) * 4 + (slot & 3)
			match slot >> 2:
				0:
					d0[idx] = 255
				1:
					d1[idx] = 255
				_:
					d2[idx] = 255
	splat_textures.clear()
	for d in [d0, d1, d2]:
		var img := Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, d)
		_soften(img, GameConfig.terrain_splat_blur)
		splat_textures.append(ImageTexture.create_from_image(img))
	return Vector2i(sw, sh)


## Cheap blur: shrink and re-grow the weight map (native, so fast). Rounds
## off the remaining hex facets before the shader adds noisy detail.
@warning_ignore("integer_division")
func _soften(img: Image, passes: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for i in passes:
		img.resize(maxi(1, w / 2), maxi(1, h / 2), Image.INTERPOLATE_BILINEAR)
		img.resize(w, h, Image.INTERPOLATE_CUBIC)


## Terrain slot under world point `p`, clamped to the map edge.
func _slot_at(grid: HexGrid, p: Vector2) -> int:
	var o := Hex.axial_to_offset(grid.world_to_hex(p))
	o.x = clampi(o.x, 0, grid.width - 1)
	o.y = clampi(o.y, 0, grid.height - 1)
	var t := grid.get_terrain(Hex.offset_to_axial(o))
	return _slot_of_terrain.get(t, 0) if t else 0


func _noise_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 42
	n.frequency = 0.012
	n.fractal_octaves = 3
	return ImageTexture.create_from_image(n.get_seamless_image(256, 256))

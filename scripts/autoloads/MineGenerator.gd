extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  MineGenerator.gd  —  Autoload : "MineGenerator"
#
#  Génère UNE mine pour UNE parcelle. Système de PALIERS (couches géologiques,
#  1 = surface … jusqu'à parcel.num_paliers). Toutes les données minerais/couches
#  proviennent de l'autoload OreDB (source unique). La génération est SEEDÉE par
#  parcel.generation_seed → la mine correspond exactement à ce que l'intel annonce.
#
#  Trois passes :
#   1. Couches géologiques ondulées (une bande par palier, 1..num_paliers)
#   2. Filons, semés couche par couche depuis le pool OreDB restreint aux
#      present_ores de la parcelle ; rendement par tuile = OreDB.get_yield()
#   3. Murs de bedrock indestructibles (bords + fond)
# ─────────────────────────────────────────────────────────────────────────────

# ─── Largeur de la mine (en tuiles) ───────────────────────────────────────────
const MIN_WIDTH: int = 64
const MAX_WIDTH: int = 112
const SHAFT_WIDTH: int = 5

# ─── Densité des filons (filons par tuile d'aire de bande) ────────────────────
const VEIN_DENSITY: float = 0.015

# Multiplicateur de densité selon la richesse de la parcelle.
const RICHNESS_DENSITY_MULT: Dictionary = {
	ParcelData.Richness.POOR:   0.35,
	ParcelData.Richness.MEDIUM: 1.00,
	ParcelData.Richness.RICH:   2.00,
	ParcelData.Richness.LOADED: 3.80,
}

# Épaisseur (en tuiles) de la bande de chaque palier — plus profond = plus épais.
const BAND_THICKNESS: Dictionary = {
	1: [6, 9], 2: [8, 12], 3: [10, 14], 4: [12, 16],
	5: [12, 18], 6: [14, 20], 7: [16, 22], 8: [18, 26],
}

# ─── Configurable by World.gd before calling generate() ──────────────────────
var surface_height: int = 4
var shaft_center_x: int = -1

# ─── Bande géologique (plage verticale d'un palier) ───────────────────────────
class GeoBand:
	var tile:   Vector2i
	var palier: int
	var y0:     int
	var y1:     int
	func _init(t: Vector2i, p: int, top: int, bottom: int) -> void:
		tile = t
		palier = p
		y0 = top
		y1 = bottom

# ─── Données générées ─────────────────────────────────────────────────────────
var map_width:  int = 0
var map_height: int = 0
var tile_data:  Dictionary = {}     # Vector2i → Vector2i (matériau / géologie)
var ore_data:   Dictionary = {}     # Vector2i → Vector2i (minerai overlay)
var _ore_meta:  Dictionary = {}     # Vector2i → { "id": String, "y": int }
var _bands:     Array = []          # Array[GeoBand]
var _rng:       RandomNumberGenerator = RandomNumberGenerator.new()
var _mat_layer: Node = null
var _ore_layer: Node = null

# ─────────────────────────────────────────────────────────────────────────────
#  ENTRÉE PRINCIPALE
# ─────────────────────────────────────────────────────────────────────────────

func generate(parcels: Array[ParcelData]) -> void:
	tile_data.clear()
	ore_data.clear()
	_ore_meta.clear()
	_bands.clear()
	if parcels.is_empty():
		return

	var parcel: ParcelData = parcels[0]
	_rng = RandomNumberGenerator.new()
	_rng.seed = parcel.generation_seed if parcel.generation_seed != 0 else randi()

	var depth: int = clampi(parcel.num_paliers, 1, OreDB.N_PALIERS)

	map_width = _rng.randi_range(MIN_WIDTH, MAX_WIDTH) + (depth - 1) * 6

	_build_bands(depth)
	map_height = _bands[_bands.size() - 1].y1 + 2

	_fill_geology()
	_populate_veins(parcel)
	_guarantee_ore(parcel.rarest_ore)
	_generate_boundary_walls()

func populate_tilemap(mat_layer: Node, ore_layer: Node) -> void:
	_mat_layer = mat_layer
	_ore_layer = ore_layer
	mat_layer.clear()
	ore_layer.clear()
	for pos: Vector2i in tile_data:
		mat_layer.set_cell(pos, 0, tile_data[pos])
	for pos: Vector2i in ore_data:
		ore_layer.set_cell(pos, 0, ore_data[pos])

# ─────────────────────────────────────────────────────────────────────────────
#  PASSE 1 — COUCHES GÉOLOGIQUES (une bande par palier)
# ─────────────────────────────────────────────────────────────────────────────

func _build_bands(depth: int) -> void:
	var y: int = surface_height
	for p in range(1, depth + 1):
		var rng_t: Array = BAND_THICKNESS.get(p, [10, 14])
		var thick: int = _rng.randi_range(rng_t[0], rng_t[1])
		_bands.append(GeoBand.new(OreDB.layer_tile(p), p, y, y + thick))
		y += thick

func _fill_geology() -> void:
	for x in map_width:
		for y in range(surface_height, map_height - 2):
			tile_data[Vector2i(x, y)] = _layer_tile_at(x, y)
		tile_data[Vector2i(x, map_height - 2)] = OreDB.BEDROCK_TILE
		tile_data[Vector2i(x, map_height - 1)] = OreDB.BEDROCK_TILE

func _layer_tile_at(x: int, y: int) -> Vector2i:
	for i in _bands.size():
		var band: GeoBand = _bands[i]
		var wobble: int = int(round(sin(float(x) * 0.12 + float(i) * 1.3) * 2.0))
		if y < band.y1 + wobble:
			return band.tile
	return _bands[_bands.size() - 1].tile

# Palier de la couche présente à (x, y) — pour le rendement réel sous un filon.
func _palier_at(pos: Vector2i) -> int:
	return OreDB.palier_of_tile(tile_data.get(pos, _bands[0].tile))

# ─────────────────────────────────────────────────────────────────────────────
#  PASSE 2 — FILONS
# ─────────────────────────────────────────────────────────────────────────────

func _populate_veins(parcel: ParcelData) -> void:
	var density_mult: float = _parcel_density_mult(parcel)

	# Pool autorisé : les minerais réellement présents sur la parcelle.
	var allowed: Dictionary = {}
	for id in parcel.present_ores:
		allowed[id] = true

	for band: GeoBand in _bands:
		var band_h: int = band.y1 - band.y0
		if band_h <= 0:
			continue
		var area: int  = band_h * map_width
		var count: int = maxi(1, int(float(area) * VEIN_DENSITY * density_mult))

		for _i in count:
			var ore_id: String = OreDB.pick_ore(band.palier, _rng, allowed)
			if ore_id == "":
				continue
			var size: int = _vein_size(ore_id)
			var sx: int = _rng.randi_range(2, map_width - 3)
			var sy: int = _rng.randi_range(band.y0, band.y1 - 1)
			_grow_vein(Vector2i(sx, sy), ore_id, size)

# Garantit au moins un filon du minerai annoncé comme le plus rare (intel honnête).
func _guarantee_ore(ore_id: String) -> void:
	if ore_id == "":
		return
	for pos in _ore_meta:
		if _ore_meta[pos]["id"] == ore_id:
			return  # déjà présent
	var spawn: int = OreDB.get_palier(ore_id)
	for i in range(_bands.size() - 1, -1, -1):
		var band: GeoBand = _bands[i]
		if band.palier >= spawn:
			var sx: int = _rng.randi_range(2, map_width - 3)
			var sy: int = _rng.randi_range(band.y0, band.y1 - 1)
			_grow_vein(Vector2i(sx, sy), ore_id, _vein_size(ore_id))
			return

func _parcel_density_mult(parcel: ParcelData) -> float:
	var m: float = RICHNESS_DENSITY_MULT.get(parcel.richness, 1.0)
	match parcel.parcel_type:
		ParcelData.ParcelType.UNSTABLE: m *= 1.3
		ParcelData.ParcelType.RESERVED: m *= 1.2
		ParcelData.ParcelType.MYSTERY:  m *= _rng.randf_range(0.6, 1.4)
	m += float(parcel.num_paliers - 1) * 0.05
	return clampf(m, 0.2, 4.5)

# Taille de filon : les minerais rares (palier élevé) forment des filons plus petits.
func _vein_size(ore_id: String) -> int:
	var p: int = OreDB.get_palier(ore_id)
	if p <= 2:
		return _rng.randi_range(4, 9)
	if p <= 5:
		return _rng.randi_range(3, 6)
	return _rng.randi_range(2, 4)

func _grow_vein(center: Vector2i, ore_id: String, max_size: int) -> void:
	if center not in tile_data or tile_data[center] == OreDB.BEDROCK_TILE:
		return

	var atlas: Vector2i = OreDB.get_atlas(ore_id)
	var queue: Array[Vector2i] = [center]
	var visited: Dictionary = {}
	var placed: int = 0

	while not queue.is_empty() and placed < max_size:
		var idx: int = _rng.randi() % queue.size()
		var pos: Vector2i = queue[idx]
		queue.remove_at(idx)

		if pos in visited:
			continue
		visited[pos] = true
		if pos not in tile_data or tile_data[pos] == OreDB.BEDROCK_TILE:
			continue

		ore_data[pos] = atlas
		_ore_meta[pos] = { "id": ore_id, "y": OreDB.get_yield(ore_id, _palier_at(pos)) }
		placed += 1

		if _rng.randf() < 0.85 and (pos + Vector2i(1,  0)) not in visited:
			queue.append(pos + Vector2i(1,  0))
		if _rng.randf() < 0.85 and (pos + Vector2i(-1, 0)) not in visited:
			queue.append(pos + Vector2i(-1, 0))
		if _rng.randf() < 0.60 and (pos + Vector2i(0,  1)) not in visited:
			queue.append(pos + Vector2i(0,  1))
		if _rng.randf() < 0.60 and (pos + Vector2i(0, -1)) not in visited:
			queue.append(pos + Vector2i(0, -1))
		if _rng.randf() < 0.20 and (pos + Vector2i(1,  1)) not in visited:
			queue.append(pos + Vector2i(1,  1))
		if _rng.randf() < 0.20 and (pos + Vector2i(-1,-1)) not in visited:
			queue.append(pos + Vector2i(-1,-1))

# ─────────────────────────────────────────────────────────────────────────────
#  PASSE 3 — MURS DE BORDURE
# ─────────────────────────────────────────────────────────────────────────────

func _generate_boundary_walls() -> void:
	for y in range(surface_height, map_height):
		tile_data[Vector2i(0,             y)] = OreDB.BEDROCK_TILE
		tile_data[Vector2i(1,             y)] = OreDB.BEDROCK_TILE
		tile_data[Vector2i(map_width - 2, y)] = OreDB.BEDROCK_TILE
		tile_data[Vector2i(map_width - 1, y)] = OreDB.BEDROCK_TILE

# ─────────────────────────────────────────────────────────────────────────────
#  QUERIES
# ─────────────────────────────────────────────────────────────────────────────

func is_solid(pos: Vector2i) -> bool:
	return pos in tile_data

func is_bedrock(pos: Vector2i) -> bool:
	return tile_data.get(pos, Vector2i(-1, -1)) == OreDB.BEDROCK_TILE

func get_mining_time(pos: Vector2i) -> float:
	if pos in ore_data:
		return OreDB.get_mine_time(_ore_meta.get(pos, {}).get("id", ""))
	if is_bedrock(pos):
		return OreDB.BEDROCK_TIME
	return OreDB.layer_time(_palier_at(pos))

func get_resource(pos: Vector2i) -> String:
	return _ore_meta.get(pos, {}).get("id", "")

func get_yield(pos: Vector2i) -> int:
	return int(_ore_meta.get(pos, {}).get("y", 1))

func remove_tile(pos: Vector2i) -> void:
	tile_data.erase(pos)
	ore_data.erase(pos)
	_ore_meta.erase(pos)
	if _mat_layer:
		_mat_layer.erase_cell(pos)
	if _ore_layer:
		_ore_layer.erase_cell(pos)

# ─────────────────────────────────────────────────────────────────────────────
#  SURFACE HELPERS (used by World.gd)
# ─────────────────────────────────────────────────────────────────────────────

func get_shaft_left() -> int:
	var center: int = shaft_center_x if shaft_center_x >= 0 else map_width / 2
	return center - SHAFT_WIDTH / 2

func get_chest_world_pos(tile_size: int) -> Vector2:
	var chest_tile_x: int = get_shaft_left() + SHAFT_WIDTH + 2
	var chest_tile_y: int = surface_height - 2
	return Vector2(float(chest_tile_x * tile_size), float(chest_tile_y * tile_size))

func get_deposit_zone_pos(tile_size: int) -> Vector2:
	var chest: Vector2 = get_chest_world_pos(tile_size)
	return chest + Vector2(float(tile_size * 3), float(tile_size))

func get_spawn_position(tile_size: int) -> Vector2:
	var x: float = float((get_shaft_left() - 3) * tile_size + tile_size / 2)
	var y: float = float((surface_height - 1) * tile_size)
	return Vector2(x, y)

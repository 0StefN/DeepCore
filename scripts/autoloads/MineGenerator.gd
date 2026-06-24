extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  MineGenerator.gd  —  Autoload : "MineGenerator"
#
#  Génération en deux passes :
#  1. Couches géologiques (type de roche, structure verticale)
#  2. Filons de ressources (clusters organiques, densité croissante avec la profondeur)
#
#  Philosophie Coal LLC :
#  - Toutes les ressources peuvent apparaître à toutes les profondeurs
#  - Plus profond = filons plus gros + ressources rares plus fréquentes
#  - Le charbon est toujours majoritaire mais les filons profonds sont immenses
#  - Les cristaux en surface : minuscules et très rares
# ─────────────────────────────────────────────────────────────────────────────

# ─── Coordonnées atlas (tileset.png, 32x32) ───────────────────────────────────
const TILE_CLAY:         Vector2i = Vector2i(0,  0)
const TILE_LIMESTONE:    Vector2i = Vector2i(1,  0)
const TILE_GRANITE:      Vector2i = Vector2i(2,  0)
const TILE_DEEP_GRANITE: Vector2i = Vector2i(3,  0)
const TILE_VOLCANIC:     Vector2i = Vector2i(4,  0)
const TILE_BEDROCK:      Vector2i = Vector2i(5,  0)
const TILE_COAL:         Vector2i = Vector2i(6,  0)
const TILE_IRON:         Vector2i = Vector2i(7,  0)
const TILE_GOLD:         Vector2i = Vector2i(8,  0)
const TILE_GEM:          Vector2i = Vector2i(9,  0)
const TILE_CRYSTAL:      Vector2i = Vector2i(10, 0)

const TILES_PER_PARCEL: int = 30
const VEIN_ZONE_HEIGHT: int = 8
const SHAFT_WIDTH:      int = 5
const TILE_SURFACE_FLOOR: Vector2i = TILE_LIMESTONE

# ─── Configurable by World.gd before calling generate() ──────────────────────
# Set via Marker2D nodes in the scene — no code change needed.
var surface_height:  int = 4   # Tile row where the mine starts
var shaft_center_x:  int = -1  # Tile X of shaft center (-1 = auto map center)

# ─── Temps de minage (secondes / tuile) ──────────────────────────────────────
const MINING_TIMES: Dictionary = {
	Vector2i(0,  0): 0.6,
	Vector2i(1,  0): 1.2,
	Vector2i(2,  0): 2.8,
	Vector2i(3,  0): 5.5,
	Vector2i(4,  0): 9.5,
	Vector2i(5,  0): 9999.0,
	Vector2i(6,  0): 1.8,
	Vector2i(7,  0): 2.4,
	Vector2i(8,  0): 4.5,
	Vector2i(9,  0): 7.0,
	Vector2i(10, 0): 12.0,
}

# ─── Ressource droppée par chaque veine ───────────────────────────────────────
const VEIN_RESOURCES: Dictionary = {
	Vector2i(6,  0): "coal",
	Vector2i(7,  0): "iron",
	Vector2i(8,  0): "gold",
	Vector2i(9,  0): "gem",
	Vector2i(10, 0): "crystal",
}

# ─── Couche géologique interne ────────────────────────────────────────────────
class GeoLayer:
	var base_tile:  Vector2i
	var thickness:  int

	func _init(bt: Vector2i, thick: int) -> void:
		base_tile = bt
		thickness = thick

# ─── Données générées ─────────────────────────────────────────────────────────
var map_width:  int = 0
var map_height: int = 0
var tile_data:  Dictionary = {}

# ─────────────────────────────────────────────────────────────────────────────
#  ENTRÉE PRINCIPALE
# ─────────────────────────────────────────────────────────────────────────────

func generate(parcels: Array[ParcelData]) -> void:
	tile_data.clear()
	if parcels.is_empty():
		return

	map_width = parcels.size() * TILES_PER_PARCEL

	var max_depth: int = 0
	for p in parcels:
		max_depth = maxi(max_depth, _parcel_depth(p))
	map_height = surface_height + max_depth + 2

	# Pass 1 — Geological layers
	for i in parcels.size():
		_generate_column(i, parcels[i])

	# Pass 2 — Resource veins
	_populate_all_veins()

	# Pass 3 — Indestructible boundary walls (left + right edges)
	_generate_boundary_walls()

func populate_tilemap(layer: Node) -> void:
	layer.clear()
	for pos: Vector2i in tile_data:
		layer.set_cell(pos, 0, tile_data[pos])

# ─────────────────────────────────────────────────────────────────────────────
#  PASSE 1 — COUCHES GÉOLOGIQUES
# ─────────────────────────────────────────────────────────────────────────────

func _generate_column(col_index: int, parcel: ParcelData) -> void:
	var layers: Array  = _build_layer_profile(parcel)
	var start_x: int   = col_index * TILES_PER_PARCEL
	var current_y: int = surface_height

	for layer in layers:
		var geo: GeoLayer = layer
		for row in geo.thickness:
			for dx in TILES_PER_PARCEL:
				tile_data[Vector2i(start_x + dx, current_y + row)] = geo.base_tile
		current_y += geo.thickness

	# Remplir le reste avec du granit profond
	while current_y < map_height - 2:
		for dx in TILES_PER_PARCEL:
			tile_data[Vector2i(start_x + dx, current_y)] = TILE_DEEP_GRANITE
		current_y += 1

	# Deux rangées de bedrock
	for row in 2:
		for dx in TILES_PER_PARCEL:
			tile_data[Vector2i(start_x + dx, map_height - 2 + row)] = TILE_BEDROCK

func _parcel_depth(parcel: ParcelData) -> int:
	match parcel.depth_tier:
		1: return randi_range(35,  45)
		2: return randi_range(60,  80)
		3: return randi_range(95, 120)
	return 40

func _build_layer_profile(parcel: ParcelData) -> Array:
	match parcel.depth_tier:
		1: return [
			GeoLayer.new(TILE_CLAY,      randi_range(5, 9)),
			GeoLayer.new(TILE_LIMESTONE, randi_range(12, 20)),
			GeoLayer.new(TILE_GRANITE,   randi_range(10, 18)),
		]
		2: return [
			GeoLayer.new(TILE_CLAY,         randi_range(4, 7)),
			GeoLayer.new(TILE_LIMESTONE,    randi_range(10, 16)),
			GeoLayer.new(TILE_GRANITE,      randi_range(14, 22)),
			GeoLayer.new(TILE_DEEP_GRANITE, randi_range(12, 22)),
		]
		3:
			var layers: Array = [
				GeoLayer.new(TILE_CLAY,         randi_range(3, 6)),
				GeoLayer.new(TILE_LIMESTONE,    randi_range(8,  14)),
				GeoLayer.new(TILE_GRANITE,      randi_range(14, 22)),
				GeoLayer.new(TILE_DEEP_GRANITE, randi_range(20, 32)),
			]
			if parcel.soil_type == ParcelData.SoilType.VOLCANIC:
				layers.append(GeoLayer.new(TILE_VOLCANIC, randi_range(16, 26)))
			return layers
	return [GeoLayer.new(TILE_LIMESTONE, 30)]

# ─────────────────────────────────────────────────────────────────────────────
#  PASSE 2 — FILONS DE RESSOURCES
# ─────────────────────────────────────────────────────────────────────────────

func _populate_all_veins() -> void:
	var mine_depth: int = map_height - surface_height - 2

	# Parcourir la carte par zones horizontales
	var y: int = surface_height
	while y < map_height - 2:
		var zone_end: int = mini(y + VEIN_ZONE_HEIGHT, map_height - 2)

		# Profondeur relative de cette zone (0.0 = surface, 1.0 = bedrock)
		var depth_pct: float = float(y - surface_height) / float(mine_depth)

		# Nombre de filons dans cette zone — augmente avec la profondeur
		var vein_count: int = randi_range(
			int(2.0 + depth_pct * 2.0),
			int(4.0 + depth_pct * 5.0)
		)

		for _i in vein_count:
			var vein_tile: Vector2i = _pick_vein_type(depth_pct)
			var vein_size: int      = _pick_vein_size(depth_pct, vein_tile)

			# Origine du filon : position aléatoire dans la zone
			var seed_x: int = randi_range(0, map_width  - 1)
			var seed_y: int = randi_range(y, zone_end   - 1)
			_grow_vein(Vector2i(seed_x, seed_y), vein_tile, vein_size)

		y += VEIN_ZONE_HEIGHT

# ─── Croissance organique d'un filon ──────────────────────────────────────────
func _grow_vein(center: Vector2i, vein_tile: Vector2i, max_size: int) -> void:
	if center not in tile_data:
		return
	if tile_data[center] == TILE_BEDROCK:
		return

	var queue: Array[Vector2i]  = [center]
	var visited: Dictionary     = {}
	var placed: int             = 0

	while not queue.is_empty() and placed < max_size:
		# Pioche aléatoire dans la file → forme plus organique qu'un BFS pur
		var idx: int      = randi() % queue.size()
		var pos: Vector2i = queue[idx]
		queue.remove_at(idx)

		if pos in visited:
			continue
		visited[pos] = true

		if pos not in tile_data:
			continue
		if tile_data[pos] == TILE_BEDROCK:
			continue

		tile_data[pos] = vein_tile
		placed        += 1

		# Propagation avec biais horizontal (les filons sont plus larges que hauts)
		if randf() < 0.85 and (pos + Vector2i(1,  0)) not in visited:
			queue.append(pos + Vector2i(1,  0))
		if randf() < 0.85 and (pos + Vector2i(-1, 0)) not in visited:
			queue.append(pos + Vector2i(-1, 0))
		if randf() < 0.60 and (pos + Vector2i(0,  1)) not in visited:
			queue.append(pos + Vector2i(0,  1))
		if randf() < 0.60 and (pos + Vector2i(0, -1)) not in visited:
			queue.append(pos + Vector2i(0, -1))
		if randf() < 0.20 and (pos + Vector2i(1,  1)) not in visited:
			queue.append(pos + Vector2i(1,  1))
		if randf() < 0.20 and (pos + Vector2i(-1,-1)) not in visited:
			queue.append(pos + Vector2i(-1,-1))

# ─── Type de veine selon la profondeur ────────────────────────────────────────
# Toutes les ressources peuvent apparaître partout,
# mais la probabilité et la taille changent avec la profondeur.
func _pick_vein_type(depth_pct: float) -> Vector2i:
	# Poids par ressource — évolue avec la profondeur
	var w_coal:    float = maxf(0.15, 0.75 - depth_pct * 0.55)
	var w_iron:    float = 0.18 + sin(depth_pct * PI) * 0.12  # pic à mi-profondeur
	var w_gold:    float = maxf(0.01, depth_pct * 0.22 - 0.02)
	var w_gem:     float = maxf(0.005, depth_pct * 0.18 - 0.04)
	var w_crystal: float = maxf(0.002, depth_pct * 0.14 - 0.07)

	var total: float = w_coal + w_iron + w_gold + w_gem + w_crystal
	var roll:  float = randf() * total

	if roll < w_coal:    return TILE_COAL
	roll -= w_coal
	if roll < w_iron:    return TILE_IRON
	roll -= w_iron
	if roll < w_gold:    return TILE_GOLD
	roll -= w_gold
	if roll < w_gem:     return TILE_GEM
	return TILE_CRYSTAL

# ─── Taille du filon selon la profondeur et le type ──────────────────────────
# Profond = filons énormes pour les ressources communes
# Ressources rares = toujours petites même en profondeur
func _pick_vein_size(depth_pct: float, vein_tile: Vector2i) -> int:
	var base: float = 4.0 + depth_pct * 22.0  # 4 en surface → 26 en profondeur

	match vein_tile:
		TILE_COAL:
			# Charbon : gros filons, encore plus gros en profondeur
			base *= randf_range(1.2, 2.2)
		TILE_IRON:
			# Fer : filons moyens
			base *= randf_range(0.7, 1.2)
		TILE_GOLD:
			# Or : filons modestes (précieux = rare)
			base *= randf_range(0.35, 0.65)
		TILE_GEM:
			# Gemmes : petits filons
			base *= randf_range(0.25, 0.50)
		TILE_CRYSTAL:
			# Cristaux : très petits, presque des pépites
			base *= randf_range(0.15, 0.35)

	return maxi(2, int(base))

# ─────────────────────────────────────────────────────────────────────────────
#  QUERIES
# ─────────────────────────────────────────────────────────────────────────────

func is_solid(pos: Vector2i) -> bool:
	return pos in tile_data

func is_bedrock(pos: Vector2i) -> bool:
	return tile_data.get(pos, Vector2i(-1, -1)) == TILE_BEDROCK

func get_mining_time(pos: Vector2i) -> float:
	var tile: Vector2i = tile_data.get(pos, Vector2i(-1, -1))
	return MINING_TIMES.get(tile, 1.0)

func get_resource(pos: Vector2i) -> String:
	var tile: Vector2i = tile_data.get(pos, Vector2i(-1, -1))
	return VEIN_RESOURCES.get(tile, "")

func remove_tile(pos: Vector2i, layer: Node) -> void:
	tile_data.erase(pos)
	layer.erase_cell(pos)

# ─────────────────────────────────────────────────────────────────────────────
#  SURFACE GENERATION
# ─────────────────────────────────────────────────────────────────────────────

func _generate_boundary_walls() -> void:
	# Indestructible bedrock walls on left and right, mine only (below surface).
	# The surface area is hand-painted in the editor — don't touch it.
	for y in range(surface_height, map_height):
		tile_data[Vector2i(0,             y)] = TILE_BEDROCK
		tile_data[Vector2i(1,             y)] = TILE_BEDROCK
		tile_data[Vector2i(map_width - 2, y)] = TILE_BEDROCK
		tile_data[Vector2i(map_width - 1, y)] = TILE_BEDROCK

# ─────────────────────────────────────────────────────────────────────────────
#  SURFACE HELPERS (used by World.gd to position chest, deposit zone, etc.)
# ─────────────────────────────────────────────────────────────────────────────

# X tile of the left edge of the shaft
func get_shaft_left() -> int:
	var center: int = shaft_center_x if shaft_center_x >= 0 else map_width / 2
	return center - SHAFT_WIDTH / 2

# World position of the chest (right of shaft, on the surface floor)
func get_chest_world_pos(tile_size: int) -> Vector2:
	var chest_tile_x: int = get_shaft_left() + SHAFT_WIDTH + 2
	var chest_tile_y: int = surface_height - 2  # one tile above the floor
	return Vector2(float(chest_tile_x * tile_size), float(chest_tile_y * tile_size))

# World position of the deposit zone center (around the chest)
func get_deposit_zone_pos(tile_size: int) -> Vector2:
	var chest: Vector2 = get_chest_world_pos(tile_size)
	return chest + Vector2(float(tile_size * 3), float(tile_size))

# Player spawns to the left of the shaft on the surface floor
func get_spawn_position(tile_size: int) -> Vector2:
	var x: float = float((get_shaft_left() - 3) * tile_size + tile_size / 2)
	var y: float = float((surface_height - 1) * tile_size)  # feet on surface floor
	return Vector2(x, y)

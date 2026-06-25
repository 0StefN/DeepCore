extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  MineGenerator.gd  —  Autoload : "MineGenerator"
#
#  Génère UNE mine correspondant à UNE parcelle (celle remportée par le joueur).
#  La largeur horizontale est une variable propre à la génération (pas liée au
#  nombre de parcelles), avec un minimum garanti.
#
#  Trois passes :
#   1. Couches géologiques ondulées (profil dérivé du tier de profondeur)
#   2. Filons de ressources, semés bande par bande selon la rareté de la couche
#   3. Murs de bedrock indestructibles (bords + fond)
#
#  Philosophie Coal LLC :
#   - Le RENDEMENT par bloc dépend de la couche : surface = 1, plus profond = plus.
#   - La RARETÉ d'apparition et la TAILLE des filons dépendent de la couche.
#   - La parcelle (hint + type) influence quelles ressources et en quelle densité.
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

# ─── Largeur de la mine (en tuiles) ───────────────────────────────────────────
const MIN_WIDTH: int = 64    # minimum garanti — jamais plus étroit que ça
const MAX_WIDTH: int = 112
const SHAFT_WIDTH: int = 5

# ─── Densité des filons (filons par tuile d'aire de bande) ────────────────────
const VEIN_DENSITY: float = 0.011

# ─── Rendement par bloc selon la couche géologique (style Coal LLC) ───────────
# C'est la QUANTITÉ de minerai que rapporte chaque bloc miné, selon la couche
# dans laquelle il se trouve. Plus on descend, plus ça rapporte.
const LAYER_YIELD: Dictionary = {
	TILE_CLAY:         1,
	TILE_LIMESTONE:    1,
	TILE_GRANITE:      2,
	TILE_DEEP_GRANITE: 3,
	TILE_VOLCANIC:     5,
}

# ─── Rareté & taille des filons par couche ────────────────────────────────────
# Pour chaque couche : liste d'entrées [tile_ressource, poids, taille_min, taille_max].
# Le poids = probabilité relative d'apparition. La taille = nb de blocs du filon.
# Plus on descend : ressources rares plus fréquentes ET filons plus gros.
const LAYER_VEINS: Dictionary = {
	TILE_CLAY: [
		[TILE_COAL, 80, 4, 8],
		[TILE_IRON, 20, 2, 4],
	],
	TILE_LIMESTONE: [
		[TILE_COAL, 60, 5, 10],
		[TILE_IRON, 35, 3, 6],
		[TILE_GOLD,  5, 1, 2],
	],
	TILE_GRANITE: [
		[TILE_COAL, 35, 4, 9],
		[TILE_IRON, 40, 4, 8],
		[TILE_GOLD, 18, 2, 4],
		[TILE_GEM,   7, 1, 3],
	],
	TILE_DEEP_GRANITE: [
		[TILE_COAL,    20, 5, 12],
		[TILE_IRON,    30, 4, 9],
		[TILE_GOLD,    28, 3, 6],
		[TILE_GEM,     15, 2, 4],
		[TILE_CRYSTAL,  7, 1, 3],
	],
	TILE_VOLCANIC: [
		[TILE_COAL,     8, 6, 14],
		[TILE_IRON,    18, 5, 10],
		[TILE_GOLD,    30, 4, 7],
		[TILE_GEM,     26, 3, 6],
		[TILE_CRYSTAL, 18, 2, 5],
	],
}

# ─── Configurable by World.gd before calling generate() ──────────────────────
var surface_height: int = 4   # Tile row where the mine starts
var shaft_center_x: int = -1  # Tile X of shaft center (-1 = auto map center)

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

# Mapping ResourceHint d'une parcelle → tuile ressource (pour le biais de hint)
const HINT_TO_TILE: Dictionary = {
	ParcelData.ResourceHint.COAL:    TILE_COAL,
	ParcelData.ResourceHint.IRON:    TILE_IRON,
	ParcelData.ResourceHint.GOLD:    TILE_GOLD,
	ParcelData.ResourceHint.GEM:     TILE_GEM,
	ParcelData.ResourceHint.CRYSTAL: TILE_CRYSTAL,
}

# ─── Bande géologique (plage verticale d'une couche) ──────────────────────────
class GeoBand:
	var tile: Vector2i
	var y0:   int   # haut inclus
	var y1:   int   # bas exclu
	func _init(t: Vector2i, top: int, bottom: int) -> void:
		tile = t
		y0   = top
		y1   = bottom

# ─── Données générées ─────────────────────────────────────────────────────────
var map_width:  int = 0
var map_height: int = 0
var tile_data:  Dictionary = {}     # Vector2i → Vector2i (atlas coords)
var _bands:     Array = []          # Array[GeoBand], du haut vers le bas

# ─────────────────────────────────────────────────────────────────────────────
#  ENTRÉE PRINCIPALE
# ─────────────────────────────────────────────────────────────────────────────

func generate(parcels: Array[ParcelData]) -> void:
	tile_data.clear()
	_bands.clear()
	if parcels.is_empty():
		return

	# Une mine = une parcelle. On prend la première fournie.
	var parcel: ParcelData = parcels[0]

	# Largeur horizontale : variable, avec minimum garanti, élargie en profondeur.
	map_width = randi_range(MIN_WIDTH, MAX_WIDTH) + (parcel.depth_tier - 1) * 10

	var mine_depth: int = _parcel_depth(parcel)
	map_height = surface_height + mine_depth + 2

	# Passe 1 — couches géologiques ondulées
	_build_bands(parcel)
	_fill_geology()

	# Passe 2 — filons de ressources, bande par bande
	_populate_veins(parcel)

	# Passe 3 — murs de bedrock indestructibles
	_generate_boundary_walls()

func populate_tilemap(layer: Node) -> void:
	layer.clear()
	for pos: Vector2i in tile_data:
		layer.set_cell(pos, 0, tile_data[pos])

# ─────────────────────────────────────────────────────────────────────────────
#  PASSE 1 — COUCHES GÉOLOGIQUES
# ─────────────────────────────────────────────────────────────────────────────

func _parcel_depth(parcel: ParcelData) -> int:
	match parcel.depth_tier:
		1: return randi_range(35,  45)
		2: return randi_range(60,  80)
		3: return randi_range(95, 120)
	return 40

# Construit la pile de bandes (plages verticales absolues) pour la parcelle.
func _build_bands(parcel: ParcelData) -> void:
	var profile: Array = _build_layer_profile(parcel)  # [[tile, thickness], …]
	var y: int = surface_height

	for entry in profile:
		var tile: Vector2i = entry[0]
		var thick: int     = entry[1]
		_bands.append(GeoBand.new(tile, y, y + thick))
		y += thick

	# Le reste jusqu'au bedrock = granit profond
	if y < map_height - 2:
		_bands.append(GeoBand.new(TILE_DEEP_GRANITE, y, map_height - 2))

func _build_layer_profile(parcel: ParcelData) -> Array:
	match parcel.depth_tier:
		1: return [
			[TILE_CLAY,      randi_range(5, 9)],
			[TILE_LIMESTONE, randi_range(12, 20)],
			[TILE_GRANITE,   randi_range(10, 18)],
		]
		2: return [
			[TILE_CLAY,         randi_range(4, 7)],
			[TILE_LIMESTONE,    randi_range(10, 16)],
			[TILE_GRANITE,      randi_range(14, 22)],
			[TILE_DEEP_GRANITE, randi_range(12, 22)],
		]
		3:
			var layers: Array = [
				[TILE_CLAY,         randi_range(3, 6)],
				[TILE_LIMESTONE,    randi_range(8,  14)],
				[TILE_GRANITE,      randi_range(14, 22)],
				[TILE_DEEP_GRANITE, randi_range(20, 32)],
			]
			if parcel.soil_type == ParcelData.SoilType.VOLCANIC:
				layers.append([TILE_VOLCANIC, randi_range(16, 26)])
			return layers
	return [[TILE_LIMESTONE, 30]]

# Remplit toute la grille avec la roche de couche (ondulée), puis le bedrock du fond.
func _fill_geology() -> void:
	for x in map_width:
		for y in range(surface_height, map_height - 2):
			tile_data[Vector2i(x, y)] = _layer_tile_at(x, y)
		# Deux rangées de bedrock au fond
		tile_data[Vector2i(x, map_height - 2)] = TILE_BEDROCK
		tile_data[Vector2i(x, map_height - 1)] = TILE_BEDROCK

# Tuile géologique à (x, y), avec frontières de couches ondulées par colonne.
# Indépendant des filons : sert aussi à connaître le rendement sous un filon.
func _layer_tile_at(x: int, y: int) -> Vector2i:
	for i in _bands.size():
		var band: GeoBand = _bands[i]
		# Chaque frontière ondule avec une phase propre → couches naturelles
		var wobble: int = int(round(sin(float(x) * 0.12 + float(i) * 1.3) * 2.0))
		if y < band.y1 + wobble:
			return band.tile
	return TILE_DEEP_GRANITE

# ─────────────────────────────────────────────────────────────────────────────
#  PASSE 2 — FILONS DE RESSOURCES
# ─────────────────────────────────────────────────────────────────────────────

func _populate_veins(parcel: ParcelData) -> void:
	var density_mult: float = _parcel_density_mult(parcel)
	var hint_tile: Vector2i = HINT_TO_TILE.get(parcel.resource_hint, Vector2i(-1, -1))

	for band: GeoBand in _bands:
		var cfg: Array = LAYER_VEINS.get(band.tile, [])
		if cfg.is_empty():
			continue

		var band_h: int  = band.y1 - band.y0
		if band_h <= 0:
			continue
		var area: int    = band_h * map_width
		var count: int   = maxi(1, int(float(area) * VEIN_DENSITY * density_mult))

		for _i in count:
			var entry: Array      = _weighted_pick(cfg, hint_tile)
			var vein_tile: Vector2i = entry[0]
			var size: int         = randi_range(entry[2], entry[3])
			var sx: int           = randi_range(2, map_width - 3)
			var sy: int           = randi_range(band.y0, band.y1 - 1)
			_grow_vein(Vector2i(sx, sy), vein_tile, size)

# Multiplicateur de densité dérivé de la parcelle (influence du bidding).
func _parcel_density_mult(parcel: ParcelData) -> float:
	var m: float = 1.0
	match parcel.parcel_type:
		ParcelData.ParcelType.UNSTABLE: m = 1.5
		ParcelData.ParcelType.RESERVED: m = 1.3
		ParcelData.ParcelType.MYSTERY:  m = randf_range(0.5, 1.8)
	# Les parcelles profondes sont un peu plus riches
	m += float(parcel.depth_tier - 1) * 0.10
	return m

# Tire une entrée de filon au hasard, pondérée, avec un biais vers le hint de parcelle.
func _weighted_pick(cfg: Array, hint_tile: Vector2i) -> Array:
	var total: float = 0.0
	for entry in cfg:
		var w: float = float(entry[1])
		if entry[0] == hint_tile:
			w *= 2.0   # la parcelle "promet" cette ressource → plus fréquente
		total += w

	var roll: float = randf() * total
	for entry in cfg:
		var w: float = float(entry[1])
		if entry[0] == hint_tile:
			w *= 2.0
		if roll < w:
			return entry
		roll -= w
	return cfg[cfg.size() - 1]

# ─── Croissance organique d'un filon ──────────────────────────────────────────
func _grow_vein(center: Vector2i, vein_tile: Vector2i, max_size: int) -> void:
	if center not in tile_data:
		return
	if tile_data[center] == TILE_BEDROCK:
		return

	var queue: Array[Vector2i] = [center]
	var visited: Dictionary    = {}
	var placed: int            = 0

	while not queue.is_empty() and placed < max_size:
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
		placed += 1

		# Propagation : biais horizontal (filons plus larges que hauts)
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

# ─────────────────────────────────────────────────────────────────────────────
#  PASSE 3 — MURS DE BORDURE
# ─────────────────────────────────────────────────────────────────────────────

func _generate_boundary_walls() -> void:
	# Bedrock indestructible à gauche et à droite (mine uniquement, sous la surface).
	for y in range(surface_height, map_height):
		tile_data[Vector2i(0,             y)] = TILE_BEDROCK
		tile_data[Vector2i(1,             y)] = TILE_BEDROCK
		tile_data[Vector2i(map_width - 2, y)] = TILE_BEDROCK
		tile_data[Vector2i(map_width - 1, y)] = TILE_BEDROCK

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

# Quantité de minerai rendue par ce bloc, selon la couche géologique sous-jacente.
func get_yield(pos: Vector2i) -> int:
	var geo: Vector2i = _layer_tile_at(pos.x, pos.y)
	return LAYER_YIELD.get(geo, 1)

func remove_tile(pos: Vector2i, layer: Node) -> void:
	tile_data.erase(pos)
	layer.erase_cell(pos)

# ─────────────────────────────────────────────────────────────────────────────
#  SURFACE HELPERS (used by World.gd to position chest, deposit zone, etc.)
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

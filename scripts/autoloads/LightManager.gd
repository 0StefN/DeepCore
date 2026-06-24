extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  LightManager.gd  —  Autoload : "LightManager"
#
#  Calcule la lumière ambiante tuile par tuile, comme Terraria :
#  - La lumière part de la surface (valeur 1.0)
#  - Elle traverse l'air lentement (AIR_DECAY)
#  - Elle est bloquée rapidement par la roche (SOLID_DECAY)
#  - Elle se propage horizontalement dans les caves (H_SPREAD)
#
#  Résultat : shafts ouverts = éclairés, caves fermées = sombres
# ─────────────────────────────────────────────────────────────────────────────

const AIR_DECAY:   float = 0.97  # 3% de perte par tuile d'air → shaft de 30 = 40% luminosité
const SOLID_DECAY: float = 0.28  # 72% de perte par tuile de roche → 4 tuiles = quasi noir
const H_SPREAD:    float = 0.75  # atténuation horizontale → lumière qui "tourne" dans les caves
const H_PASSES:    int   = 3     # passes de propagation horizontale

var _ambient: Dictionary = {}    # Vector2i → float (0.0-1.0)

# ─────────────────────────────────────────────────────────────────────────────
#  CALCUL INITIAL (appelé après MineGenerator.generate)
# ─────────────────────────────────────────────────────────────────────────────

func compute_all() -> void:
	_ambient.clear()
	_pass_vertical()
	for _i in H_PASSES:
		_pass_horizontal()

func _pass_vertical() -> void:
	for x in MineGenerator.map_width:
		var light: float = 1.0
		for y in MineGenerator.map_height:
			var pos := Vector2i(x, y)
			if y < MineGenerator.surface_height:
				_ambient[pos] = 1.0
				continue
			if MineGenerator.is_solid(pos):
				light *= SOLID_DECAY
			else:
				light *= AIR_DECAY
			_ambient[pos] = clampf(light, 0.0, 1.0)

func _pass_horizontal() -> void:
	for y in range(MineGenerator.surface_height, MineGenerator.map_height):
		# Gauche → droite
		for x in range(1, MineGenerator.map_width):
			var pos := Vector2i(x, y)
			if MineGenerator.is_solid(pos):
				continue
			var left: float    = _ambient.get(Vector2i(x - 1, y), 0.0)
			var current: float = _ambient.get(pos, 0.0)
			_ambient[pos]      = maxf(current, left * H_SPREAD)
		# Droite → gauche
		for x in range(MineGenerator.map_width - 2, -1, -1):
			var pos := Vector2i(x, y)
			if MineGenerator.is_solid(pos):
				continue
			var right: float   = _ambient.get(Vector2i(x + 1, y), 0.0)
			var current: float = _ambient.get(pos, 0.0)
			_ambient[pos]      = maxf(current, right * H_SPREAD)

# ─────────────────────────────────────────────────────────────────────────────
#  MISE À JOUR LOCALE (appelée quand une tuile est minée)
# ─────────────────────────────────────────────────────────────────────────────

func update_around(tile_pos: Vector2i) -> void:
	# Recalculer une bande autour de la tuile minée
	var x_min: int = maxi(0, tile_pos.x - 6)
	var x_max: int = mini(MineGenerator.map_width - 1, tile_pos.x + 6)

	for x in range(x_min, x_max + 1):
		_recompute_column(x)

	# Propagation horizontale dans la zone affectée + marge
	for _i in H_PASSES:
		_pass_horizontal_range(x_min - H_PASSES, x_max + H_PASSES)

func _recompute_column(x: int) -> void:
	var light: float = 1.0
	for y in MineGenerator.map_height:
		var pos := Vector2i(x, y)
		if y < MineGenerator.surface_height:
			_ambient[pos] = 1.0
			continue
		if MineGenerator.is_solid(pos):
			light *= SOLID_DECAY
		else:
			light *= AIR_DECAY
		_ambient[pos] = clampf(light, 0.0, 1.0)

func _pass_horizontal_range(x_from: int, x_to: int) -> void:
	var x_min: int = maxi(0, x_from)
	var x_max: int = mini(MineGenerator.map_width - 1, x_to)
	for y in range(MineGenerator.surface_height, MineGenerator.map_height):
		for x in range(x_min + 1, x_max + 1):
			var pos := Vector2i(x, y)
			if MineGenerator.is_solid(pos): continue
			var left: float = _ambient.get(Vector2i(x - 1, y), 0.0)
			_ambient[pos] = maxf(_ambient.get(pos, 0.0), left * H_SPREAD)
		for x in range(x_max - 1, x_min - 1, -1):
			var pos := Vector2i(x, y)
			if MineGenerator.is_solid(pos): continue
			var right: float = _ambient.get(Vector2i(x + 1, y), 0.0)
			_ambient[pos] = maxf(_ambient.get(pos, 0.0), right * H_SPREAD)

# ─────────────────────────────────────────────────────────────────────────────
#  QUERY
# ─────────────────────────────────────────────────────────────────────────────

func get_ambient(pos: Vector2i) -> float:
	# Above the mine surface = outdoors, always fully lit
	if pos.y < MineGenerator.surface_height:
		return 1.0
	return _ambient.get(pos, 0.0)

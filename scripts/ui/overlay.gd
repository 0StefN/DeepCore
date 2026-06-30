extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
#  Overlay.gd
#  Draws per-tile darkness and the mining highlight on top of the world.
#  Must be the last child of World so it renders above everything else.
# ─────────────────────────────────────────────────────────────────────────────

const TILE_SIZE:    int   = 32
const TORCH_TILES:  float = 4.0   # rayon de base de la torche du joueur (tuiles)
const PLACED_TORCH_TILES: float = 6.0   # rayon d'une torche posée (tuiles)
const MIN_DARKNESS: float = 0.02

var _player:        CharacterBody2D = null
var _mining:        Node            = null
var _mine_target:   Vector2i        = Vector2i(-999, -999)
var _mine_progress: float           = 0.0
var _torch_tiles:   float           = TORCH_TILES   # rayon effectif (base + Lampe de Casque)
var _torches:       Array[Vector2i] = []            # torches posées (tuiles)

# Ajoute une torche posée (appelé par World via le signal torch_placed).
func add_torch(tile: Vector2i) -> void:
	_torches.append(tile)

func _ready() -> void:
	_player = get_parent().get_node("Player")
	_mining = _player.get_node("MiningComponent")
	# Lampe de Casque : agrandit le rayon de la torche du joueur.
	# Volontairement découplé du LightManager (rework de l'éclairage prévu).
	var corp: CorporationData = GameManager.player_corporation
	if corp:
		_torch_tiles = TORCH_TILES + ResearchManager.get_effect("light_radius", corp)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	_draw_darkness()
	_draw_cracks()
	_draw_torches()
	_draw_mine_highlight()

# Contribution lumineuse (0..1) des torches posées au point donné.
func _placed_torch_light(point: Vector2) -> float:
	if _torches.is_empty():
		return 0.0
	var range_px: float = PLACED_TORCH_TILES * TILE_SIZE
	var best: float = 0.0
	for tile in _torches:
		var c := Vector2(
			float(tile.x) * TILE_SIZE + TILE_SIZE * 0.5,
			float(tile.y) * TILE_SIZE + TILE_SIZE * 0.5
		)
		var k: float = clampf(1.0 - point.distance_to(c) / range_px, 0.0, 1.0)
		best = maxf(best, k * k * k)
	return best

# Petit marqueur flamme sur chaque torche posée.
func _draw_torches() -> void:
	for tile in _torches:
		var c := Vector2(
			float(tile.x) * TILE_SIZE + TILE_SIZE * 0.5,
			float(tile.y) * TILE_SIZE + TILE_SIZE * 0.5
		)
		draw_circle(c, 5.0, Color(1.0, 0.55, 0.15, 0.95))
		draw_circle(c, 2.5, Color(1.0, 0.92, 0.55, 1.0))

# ─────────────────────────────────────────────────────────────────────────────
#  DARKNESS
# ─────────────────────────────────────────────────────────────────────────────

func _draw_darkness() -> void:
	if not _player:
		return

	var cam: Camera2D = get_viewport().get_camera_2d()
	if not cam:
		return

	var screen_size: Vector2 = get_viewport_rect().size
	var cam_pos:     Vector2 = cam.get_screen_center_position()
	var zoom:        float   = cam.zoom.x
	var half:        Vector2 = screen_size / (2.0 * zoom)

	var min_tile := Vector2i(
		floori((cam_pos.x - half.x) / TILE_SIZE) - 1,
		floori((cam_pos.y - half.y) / TILE_SIZE) - 1
	)
	var max_tile := Vector2i(
		ceili((cam_pos.x + half.x) / TILE_SIZE) + 1,
		ceili((cam_pos.y + half.y) / TILE_SIZE) + 1
	)

	var player_pos:     Vector2 = _player.global_position
	var torch_range_px: float   = _torch_tiles * TILE_SIZE

	for x in range(min_tile.x, max_tile.x + 1):
		for y in range(min_tile.y, max_tile.y + 1):
			var pos := Vector2i(x, y)
			var ambient: float = LightManager.get_ambient(pos)

			var tile_center: Vector2 = Vector2(
				float(x) * TILE_SIZE + TILE_SIZE * 0.5,
				float(y) * TILE_SIZE + TILE_SIZE * 0.5
			)
			var dist: float  = tile_center.distance_to(player_pos)
			var t: float     = clampf(1.0 - dist / torch_range_px, 0.0, 1.0)
			var torch: float = t * t * t

			# Torches posées : sources ponctuelles supplémentaires (max de toutes).
			var placed: float = _placed_torch_light(tile_center)

			var light:    float = maxf(maxf(ambient, torch), placed)
			var darkness: float = 1.0 - light

			if darkness > MIN_DARKNESS:
				draw_rect(
					Rect2(Vector2(float(x) * TILE_SIZE, float(y) * TILE_SIZE),
						  Vector2(TILE_SIZE, TILE_SIZE)),
					Color(0.0, 0.0, 0.02, darkness)
				)

# ─────────────────────────────────────────────────────────────────────────────
#  MINING HIGHLIGHT
# ─────────────────────────────────────────────────────────────────────────────

func _draw_mine_highlight() -> void:
	if _mine_target == Vector2i(-999, -999) or not _mining:
		return

	var tile_world: Vector2 = Vector2(
		float(_mine_target.x) * TILE_SIZE,
		float(_mine_target.y) * TILE_SIZE
	)
	var rect: Rect2 = Rect2(tile_world, Vector2(TILE_SIZE, TILE_SIZE))

	var player_tile: Vector2i = Vector2i(
		floori(_player.global_position.x / TILE_SIZE),
		floori(_player.global_position.y / TILE_SIZE)
	)
	var in_range: bool = \
		abs(_mine_target.x - player_tile.x) <= MiningComponent.MINE_RANGE and \
		abs(_mine_target.y - player_tile.y) <= MiningComponent.MINE_RANGE

	if not in_range:
		draw_rect(rect, Color(1.0, 0.2, 0.2, 0.25), true)
		draw_rect(rect, Color(1.0, 0.2, 0.2, 0.70), false, 2.0)
		return

	if MineGenerator.is_bedrock(_mine_target) or not MineGenerator.is_solid(_mine_target):
		return

	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.20), true)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.85), false, 2.0)

# ─────────────────────────────────────────────────────────────────────────────
#  CRAQUELURES (vie du bloc — persistante)
# ─────────────────────────────────────────────────────────────────────────────

func _draw_cracks() -> void:
	if not _mining:
		return
	var blocks: Dictionary = _mining.get_damaged_blocks()
	for tile in blocks.keys():
		_draw_tile_cracks(tile, blocks[tile])

func _draw_tile_cracks(tile: Vector2i, p: float) -> void:
	if p <= 0.05:
		return
	var origin := Vector2(float(tile.x) * TILE_SIZE, float(tile.y) * TILE_SIZE)
	var center := origin + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	var n: int = clampi(int(p * 6.0) + 1, 1, 5)   # de plus en plus de craquelures
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tile)                          # motif stable par bloc
	var col := Color(0.04, 0.03, 0.05, clampf(0.40 + p * 0.50, 0.0, 0.92))
	var w: float = 1.0 + p * 1.5
	for _i in range(n):
		var ang: float   = rng.randf() * TAU
		var l1: float    = TILE_SIZE * (0.22 + rng.randf() * 0.22)
		var mid: Vector2 = center + Vector2(cos(ang), sin(ang)) * l1
		var ang2: float  = ang + rng.randf_range(-0.8, 0.8)
		var endp: Vector2 = mid + Vector2(cos(ang2), sin(ang2)) * (TILE_SIZE * 0.30)
		draw_line(center, mid, col, w)
		draw_line(mid, endp, col, w)

func _on_mine_target_changed(tile_pos: Vector2i, progress: float) -> void:
	_mine_target   = tile_pos
	_mine_progress = progress

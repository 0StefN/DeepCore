extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
#  Overlay.gd
#  Draws per-tile darkness and the mining highlight on top of the world.
#  Must be the last child of World so it renders above everything else.
# ─────────────────────────────────────────────────────────────────────────────

const TILE_SIZE:    int   = 32
const TORCH_TILES:  float = 10.0
const MIN_DARKNESS: float = 0.02

var _player:        CharacterBody2D = null
var _mining:        Node            = null
var _mine_target:   Vector2i        = Vector2i(-999, -999)
var _mine_progress: float           = 0.0

func _ready() -> void:
	_player = get_parent().get_node("Player")
	_mining = _player.get_node("MiningComponent")

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	_draw_darkness()
	_draw_mine_highlight()

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
	var torch_range_px: float   = TORCH_TILES * TILE_SIZE

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

			var light:    float = maxf(ambient, torch)
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

	if _mine_progress > 0.01:
		var bar_w: float = TILE_SIZE * clampf(_mine_progress, 0.0, 1.0)
		draw_rect(
			Rect2(tile_world + Vector2(0.0, TILE_SIZE - 5.0), Vector2(TILE_SIZE, 5.0)),
			Color(0.0, 0.0, 0.0, 0.7), true
		)
		draw_rect(
			Rect2(tile_world + Vector2(0.0, TILE_SIZE - 5.0), Vector2(bar_w, 5.0)),
			Color(1.0, 0.85, 0.1), true
		)

func _on_mine_target_changed(tile_pos: Vector2i, progress: float) -> void:
	_mine_target   = tile_pos
	_mine_progress = progress

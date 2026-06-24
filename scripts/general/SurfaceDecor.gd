extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
#  SurfaceDecor.gd
#  Draws placeholder surface decorations: chest, shaft border, signs.
#  Add as child of World, BEFORE Overlay so it renders below the darkness.
#  Replace draw calls with proper sprites later.
# ─────────────────────────────────────────────────────────────────────────────

const TILE_SIZE: int = 32

var _chest_pos:      Vector2 = Vector2.ZERO
var _shaft_left_px:  float   = 0.0
var _shaft_right_px: float   = 0.0
var _floor_y_px:     float   = 0.0

func setup() -> void:
	_chest_pos     = MineGenerator.get_chest_world_pos(TILE_SIZE)
	_shaft_left_px = float(MineGenerator.get_shaft_left() * TILE_SIZE)
	_shaft_right_px = _shaft_left_px + float(MineGenerator.SHAFT_WIDTH * TILE_SIZE)
	_floor_y_px    = float((MineGenerator.SURFACE_HEIGHT - 1) * TILE_SIZE)
	queue_redraw()

func _draw() -> void:
	_draw_shaft_borders()
	_draw_chest()
	_draw_deposit_hint()

func _draw_shaft_borders() -> void:
	# Wooden beams framing the shaft opening
	var beam_color: Color = Color(0.45, 0.28, 0.12)
	var beam_w:     float = 6.0
	var beam_top:   float = _floor_y_px - float(TILE_SIZE)

	# Left beam
	draw_rect(
		Rect2(_shaft_left_px - beam_w, beam_top, beam_w, float(TILE_SIZE)),
		beam_color
	)
	# Right beam
	draw_rect(
		Rect2(_shaft_right_px, beam_top, beam_w, float(TILE_SIZE)),
		beam_color
	)
	# Top crossbar
	draw_rect(
		Rect2(_shaft_left_px - beam_w, beam_top - 6.0,
			  _shaft_right_px - _shaft_left_px + beam_w * 2.0, 6.0),
		beam_color
	)

func _draw_chest() -> void:
	var x: float = _chest_pos.x
	var y: float = _chest_pos.y
	var w: float = float(TILE_SIZE) * 1.5
	var h: float = float(TILE_SIZE)

	# Chest body
	draw_rect(Rect2(x, y, w, h), Color(0.55, 0.35, 0.12))
	# Chest lid (slightly lighter)
	draw_rect(Rect2(x, y, w, h * 0.35), Color(0.65, 0.42, 0.15))
	# Chest border
	draw_rect(Rect2(x, y, w, h), Color(0.3, 0.18, 0.06), false, 2.0)
	# Lock
	draw_rect(
		Rect2(x + w * 0.5 - 4.0, y + h * 0.35 - 4.0, 8.0, 8.0),
		Color(0.8, 0.7, 0.2)
	)
	# Hinges
	draw_rect(Rect2(x + 4.0,       y + h * 0.35 - 3.0, 6.0, 6.0), Color(0.6, 0.5, 0.2))
	draw_rect(Rect2(x + w - 10.0,  y + h * 0.35 - 3.0, 6.0, 6.0), Color(0.6, 0.5, 0.2))

func _draw_deposit_hint() -> void:
	# Small arrow pointing toward chest when player approaches
	# (simple placeholder — replace with animated sprite later)
	var label_pos: Vector2 = _chest_pos + Vector2(float(TILE_SIZE) * 0.75, -20.0)
	draw_string(
		ThemeDB.fallback_font,
		label_pos,
		"CHEST",
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		11,
		Color(0.9, 0.8, 0.4)
	)

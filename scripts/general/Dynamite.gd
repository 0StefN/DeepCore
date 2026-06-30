class_name Dynamite
extends Node2D

# Charge posée : compte à rebours (mèche) puis émet `detonated`.
# La destruction des blocs / drops est gérée par World (qui a accès aux couches).

signal detonated

const TILE_SIZE:  int   = 32
const FUSE_TIME:  float = 1.6
const FLASH_TIME: float = 0.25

var _radius_px: float = 32.0   # rayon visuel du flash
var _fuse:      float = FUSE_TIME
var _flashing:  bool  = false
var _flash:     float = 0.0

func setup(radius_tiles: float) -> void:
	_radius_px = radius_tiles * TILE_SIZE

func _process(delta: float) -> void:
	if _flashing:
		_flash += delta
		if _flash >= FLASH_TIME:
			queue_free()
		queue_redraw()
		return

	_fuse -= delta
	if _fuse <= 0.0:
		_flashing = true
		detonated.emit()
	queue_redraw()

func _draw() -> void:
	if _flashing:
		var k: float = clampf(_flash / FLASH_TIME, 0.0, 1.0)
		var r: float = lerpf(TILE_SIZE * 0.4, _radius_px, k)
		draw_circle(Vector2.ZERO, r,        Color(1.0, 0.55, 0.15, (1.0 - k) * 0.55))
		draw_circle(Vector2.ZERO, r * 0.55, Color(1.0, 0.9, 0.5,  (1.0 - k) * 0.8))
		return

	# Bâton de dynamite + mèche clignotante (accélère vers la fin).
	draw_rect(Rect2(-5.0, -8.0, 10.0, 16.0), Color(0.74, 0.16, 0.13))
	draw_rect(Rect2(-5.0, -8.0, 10.0, 16.0), Color(0.95, 0.85, 0.85, 0.5), false, 1.0)
	var period: float = clampf(_fuse * 0.18, 0.07, 0.22)
	if fmod(_fuse, period) < period * 0.5:
		draw_circle(Vector2(0.0, -11.0), 2.6, Color(1.0, 0.85, 0.2))

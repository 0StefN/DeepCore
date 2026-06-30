class_name ResourceDrop
extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
#  ResourceDrop.gd
#  A piece of ore dropped on the ground after a block is mined.
#
#  Behaviour:
#  - Pops out with a little scatter, falls under gravity, rests on solid tiles.
#  - When the player is within the (upgradable) magnet radius AND has room in
#    their bag, it accelerates toward the player and is picked up on contact.
#  - If the bag is full, it stays on the ground and remains pickable later.
#  - Pickup is partial: it adds as many units as fit, keeps the rest.
#
#  Wiring: instantiated by World.gd via setup(); no editor configuration needed.
# ─────────────────────────────────────────────────────────────────────────────

const TILE_SIZE: int = 32

const GRAVITY:       float = 900.0
const MAX_FALL:      float = 600.0
const REST_FRICTION: float = 7.0     # horizontal damping once spawned

# Magnet — base radius is 1 tile; bonus comes from R&D (upgradable later).
const BASE_MAGNET_TILES: float = 1.0
const MAGNET_MIN_SPEED:  float = 60.0
const MAGNET_MAX_SPEED:  float = 520.0
const PICKUP_DIST:       float = 7.0

var resource: String = ""
var amount:   int    = 0

var _velocity:  Vector2 = Vector2.ZERO
var _resting:   bool    = false
var _player:    Node2D  = null
var _inventory: Node    = null
var _no_pickup_time: float = 0.0   # tant que > 0, l'aimant ne peut pas reprendre l'objet

# ─── Placeholder colours : centralisées dans OreDB (voir _draw) ──────────────

# ─── Custom drop art (optional) ───────────────────────────────────────────────
# To give a resource its own sprite instead of the coloured placeholder:
#   1. Put the PNG somewhere in the project, e.g. assets/textures/drops/coal.png
#   2. Add a line below, e.g.:  "coal": preload("res://assets/textures/drops/coal.png"),
# Any resource without an entry here keeps the coloured square.
# DROP_SIZE_PX controls the on-screen size; the sprite is scaled to fit it.
const DROP_SIZE_PX: float = 16.0
const RESOURCE_TEXTURES: Dictionary = {
	 "coal":    preload("res://assets/resources/drops/coal_drop.png")
	# "iron":    preload("res://assets/textures/drops/iron.png"),
	# "gold":    preload("res://assets/textures/drops/gold.png"),
	# "gem":     preload("res://assets/textures/drops/gem.png"),
	# "crystal": preload("res://assets/textures/drops/crystal.png"),
}

var _sprite: Sprite2D = null   # created in setup() when a texture is configured

# ─────────────────────────────────────────────────────────────────────────────

func setup(res: String, amt: int, player: Node2D, inventory: Node, pickup_delay: float = 0.0) -> void:
	resource   = res
	amount     = amt
	_player    = player
	_inventory = inventory
	_no_pickup_time = pickup_delay
	# Little pop so drops scatter instead of stacking on one pixel
	_velocity = Vector2(randf_range(-70.0, 70.0), randf_range(-180.0, -90.0))
	_setup_sprite()
	queue_redraw()

# Builds a Sprite2D if this resource has custom art; otherwise the placeholder
# square (in _draw) is used.
func _setup_sprite() -> void:
	var tex: Texture2D = RESOURCE_TEXTURES.get(resource, null)
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.show_behind_parent = true   # keep the count badge (in _draw) on top
	var ts: Vector2 = tex.get_size()
	if ts.x > 0.0 and ts.y > 0.0:
		var s: float = DROP_SIZE_PX / maxf(ts.x, ts.y)
		_sprite.scale = Vector2(s, s)
	add_child(_sprite)

func _process(delta: float) -> void:
	if amount <= 0:
		queue_free()
		return

	if _no_pickup_time > 0.0:
		_no_pickup_time -= delta

	if _can_magnetize():
		_do_magnet(delta)
	else:
		_do_physics(delta)

	queue_redraw()

# ─────────────────────────────────────────────────────────────────────────────
#  MAGNET
# ─────────────────────────────────────────────────────────────────────────────

func _can_magnetize() -> bool:
	if not _player or not _inventory:
		return false
	if _no_pickup_time > 0.0:
		return false
	if _inventory.is_full():
		return false
	return global_position.distance_to(_player.global_position) <= _magnet_radius_px()

func _magnet_radius_px() -> float:
	var bonus: float = 0.0
	# Upgradable hook: a future R&D node with effect_key "pickup_radius" feeds this.
	if ResearchManager.has_method("get_pickup_radius_bonus"):
		bonus = ResearchManager.get_pickup_radius_bonus(GameManager.player_corporation)
	return (BASE_MAGNET_TILES + bonus) * float(TILE_SIZE)

func _do_magnet(delta: float) -> void:
	_resting = false
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float        = to_player.length()

	if dist <= PICKUP_DIST:
		_try_pickup()
		return

	# Speed ramps up as the drop gets closer to the player
	var radius: float = _magnet_radius_px()
	var t: float      = clampf(1.0 - dist / radius, 0.0, 1.0)
	var speed: float  = lerpf(MAGNET_MIN_SPEED, MAGNET_MAX_SPEED, t * t)
	global_position += to_player.normalized() * speed * delta

func _try_pickup() -> void:
	while amount > 0 and _inventory.try_add(resource):
		amount -= 1
	if amount <= 0:
		queue_free()
	# If amount remains, the bag filled up — the drop stays where it is.

# ─────────────────────────────────────────────────────────────────────────────
#  PHYSICS (gravity + rest on solid ground)
# ─────────────────────────────────────────────────────────────────────────────

func _do_physics(delta: float) -> void:
	if _resting:
		# Still supported? If the block underneath was mined away, fall again.
		var ground := Vector2i(
			floori(global_position.x / TILE_SIZE),
			floori((global_position.y + 6.0 + 1.0) / TILE_SIZE)
		)
		if MineGenerator.is_solid(ground):
			return
		_resting = false

	_velocity.y = minf(_velocity.y + GRAVITY * delta, MAX_FALL)
	_velocity.x = move_toward(_velocity.x, 0.0, REST_FRICTION * 60.0 * delta)

	var next_pos: Vector2 = global_position + _velocity * delta

	# Tile just below the drop's lower edge
	var below := Vector2i(
		floori(next_pos.x / TILE_SIZE),
		floori((next_pos.y + 6.0) / TILE_SIZE)
	)

	if _velocity.y > 0.0 and MineGenerator.is_solid(below):
		# Snap to sit on top of that solid tile
		global_position.x = next_pos.x
		global_position.y = float(below.y * TILE_SIZE) - 6.0
		_velocity = Vector2.ZERO
		_resting = true
	else:
		global_position = next_pos

# ─────────────────────────────────────────────────────────────────────────────
#  DRAW (placeholder)
# ─────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Placeholder square only when no custom sprite is configured
	if _sprite == null:
		var col: Color = OreDB.get_color(resource)
		var s: float = 11.0
		var r := Rect2(-s * 0.5, -s * 0.5, s, s)
		draw_rect(r, col, true)
		draw_rect(r, col.lightened(0.35), false, 1.5)

	# Tiny count badge for stacks > 1
	if amount > 1:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(DROP_SIZE_PX * 0.5 - 2.0, -DROP_SIZE_PX * 0.5),
			str(amount),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(1, 1, 1, 0.9)
		)

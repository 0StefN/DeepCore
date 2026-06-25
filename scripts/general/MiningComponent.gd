class_name MiningComponent
extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  MiningComponent.gd
#  Handles all mouse-based mining logic for the player.
#  Communicates via signals — no direct references to siblings.
#
#  Wiring (done in World.gd):
#    drop_spawned    → World._on_drop_spawned() (instantiates a ResourceDrop)
#    tile_broken     → LightManager.update_around()
#    mine_target_changed → Overlay._on_mine_target_changed()
# ─────────────────────────────────────────────────────────────────────────────

const TILE_SIZE:  int = 32
const MINE_RANGE: int = 4

var tile_layer: Node = null   # assigned by World.gd after scene setup

var _target:   Vector2i = Vector2i(-999, -999)
var _progress: float    = 0.0

# Parent reference (CharacterBody2D — used for position + mouse coords)
var _body: CharacterBody2D = null

signal mine_target_changed(tile_pos: Vector2i, progress: float)
signal tile_broken(tile_pos: Vector2i)
# Émis quand un bloc de ressource est cassé. La quantité dépend de la couche
# géologique (rendement Coal LLC). Le câblage (instanciation du drop) est dans World.gd.
signal drop_spawned(resource: String, amount: int, world_pos: Vector2)

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_body = get_parent() as CharacterBody2D

func _process(delta: float) -> void:
	_handle_mining(delta)

# ─────────────────────────────────────────────────────────────────────────────
#  MINING
# ─────────────────────────────────────────────────────────────────────────────

func _handle_mining(delta: float) -> void:
	var hovered:     Vector2i = get_hovered_tile()
	var player_tile: Vector2i = _get_player_tile()

	var in_range: bool = \
		abs(hovered.x - player_tile.x) <= MINE_RANGE and \
		abs(hovered.y - player_tile.y) <= MINE_RANGE

	var can_mine: bool = in_range \
		and MineGenerator.is_solid(hovered) \
		and not MineGenerator.is_bedrock(hovered)

	if not can_mine or not Input.is_action_pressed("mine_click"):
		_reset()
		return

	if hovered != _target:
		_progress = 0.0
		_target   = hovered

	var base_time:      float = MineGenerator.get_mining_time(_target)
	var speed_bonus:    float = ResearchManager.get_mining_speed_bonus(
		GameManager.player_corporation
	)
	var effective_time: float = base_time / maxf(1.0 + speed_bonus, 0.1)

	_progress += delta / effective_time
	mine_target_changed.emit(_target, _progress)

	if _progress >= 1.0:
		_break(_target)

func _reset() -> void:
	if _target != Vector2i(-999, -999):
		_target   = Vector2i(-999, -999)
		_progress = 0.0
		mine_target_changed.emit(_target, 0.0)

func _break(tile_pos: Vector2i) -> void:
	var resource: String = MineGenerator.get_resource(tile_pos)
	var amount:   int    = MineGenerator.get_yield(tile_pos)

	if tile_layer:
		MineGenerator.remove_tile(tile_pos, tile_layer)

	if resource != "" and amount > 0:
		var center := Vector2(
			float(tile_pos.x * TILE_SIZE) + TILE_SIZE * 0.5,
			float(tile_pos.y * TILE_SIZE) + TILE_SIZE * 0.5
		)
		drop_spawned.emit(resource, amount, center)

	tile_broken.emit(tile_pos)
	_reset()

# ─────────────────────────────────────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func get_hovered_tile() -> Vector2i:
	var mouse: Vector2 = _body.get_global_mouse_position()
	return Vector2i(floori(mouse.x / TILE_SIZE), floori(mouse.y / TILE_SIZE))

func get_progress() -> float:
	return _progress

func _get_player_tile() -> Vector2i:
	return Vector2i(
		floori(_body.global_position.x / TILE_SIZE),
		floori(_body.global_position.y / TILE_SIZE)
	)

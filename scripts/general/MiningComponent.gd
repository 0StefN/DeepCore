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

# Outils de la barre (slot 0 = pioche/minage ; extensible plus tard façon Coal LLC)
const TOOL_PICKAXE:  int = 0
const TOOL_TORCH:    int = 1
const TOOL_DYNAMITE: int = 2

var selected_tool: int = TOOL_PICKAXE

var _target:   Vector2i = Vector2i(-999, -999)
var _progress: float    = 0.0
var _block_progress: Dictionary = {}   # Vector2i -> float : dégâts conservés par bloc

# Parent reference (CharacterBody2D — used for position + mouse coords)
var _body: CharacterBody2D = null

signal mine_target_changed(tile_pos: Vector2i, progress: float)
signal tile_broken(tile_pos: Vector2i)
signal torch_placed(tile_pos: Vector2i)
signal dynamite_placed(tile_pos: Vector2i)
signal tool_changed(index: int)
# Émis quand un bloc de ressource est cassé. La quantité dépend de la couche
# géologique (rendement Coal LLC). Le câblage (instanciation du drop) est dans World.gd.
signal drop_spawned(resource: String, amount: int, world_pos: Vector2)

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_body = get_parent() as CharacterBody2D

func _process(delta: float) -> void:
	_handle_tool_select()
	if selected_tool == TOOL_TORCH:
		_reset()            # pas de minage en mode torche
		_handle_torch()
	elif selected_tool == TOOL_DYNAMITE:
		_reset()
		_handle_dynamite()
	else:
		_handle_mining(delta)

# ─────────────────────────────────────────────────────────────────────────────
#  SÉLECTION D'OUTIL (barre d'objets — touches 1/2)
# ─────────────────────────────────────────────────────────────────────────────

func _handle_tool_select() -> void:
	var prev: int = selected_tool
	if Input.is_action_just_pressed("hotbar_1"):
		selected_tool = TOOL_PICKAXE
	elif Input.is_action_just_pressed("hotbar_2"):
		# On ne peut sélectionner la torche que si on en possède.
		var corp: CorporationData = GameManager.player_corporation
		if corp != null and corp.consumable_count("torch") > 0:
			selected_tool = TOOL_TORCH
	elif Input.is_action_just_pressed("hotbar_3"):
		var corp2: CorporationData = GameManager.player_corporation
		if corp2 != null and corp2.consumable_count("dynamite") > 0:
			selected_tool = TOOL_DYNAMITE
	if selected_tool != prev:
		tool_changed.emit(selected_tool)

# ─────────────────────────────────────────────────────────────────────────────
#  TORCHE (posée à la tuile sous le curseur, dans une case d'air à portée)
# ─────────────────────────────────────────────────────────────────────────────

func _handle_torch() -> void:
	if not Input.is_action_just_pressed("mine_click"):
		return
	var tile:        Vector2i = get_hovered_tile()
	var player_tile: Vector2i = _get_player_tile()
	var in_range: bool = \
		abs(tile.x - player_tile.x) <= MINE_RANGE and \
		abs(tile.y - player_tile.y) <= MINE_RANGE
	if not in_range:
		return
	if MineGenerator.is_solid(tile):
		return   # on pose la torche dans une case vide (air)
	var corp: CorporationData = GameManager.player_corporation
	if corp == null or not corp.use_consumable("torch"):
		return   # plus de torches
	torch_placed.emit(tile)
	# Plus de torches en stock → on revient automatiquement à la pioche.
	if corp.consumable_count("torch") <= 0:
		selected_tool = TOOL_PICKAXE
		tool_changed.emit(selected_tool)

# ─────────────────────────────────────────────────────────────────────────────
#  DYNAMITE (posée à la tuile sous le curseur ; explose en zone après une mèche)
# ─────────────────────────────────────────────────────────────────────────────

func _handle_dynamite() -> void:
	if not Input.is_action_just_pressed("mine_click"):
		return
	var tile:        Vector2i = get_hovered_tile()
	var player_tile: Vector2i = _get_player_tile()
	var in_range: bool = \
		abs(tile.x - player_tile.x) <= MINE_RANGE and \
		abs(tile.y - player_tile.y) <= MINE_RANGE
	if not in_range:
		return
	if MineGenerator.is_solid(tile):
		return   # on pose dans une case d'air ; l'explosion détruit les blocs autour
	var corp: CorporationData = GameManager.player_corporation
	if corp == null or not corp.use_consumable("dynamite"):
		return
	dynamite_placed.emit(tile)
	if corp.consumable_count("dynamite") <= 0:
		selected_tool = TOOL_PICKAXE
		tool_changed.emit(selected_tool)

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
		_target   = hovered
		_progress = _block_progress.get(_target, 0.0)   # reprend les dégâts déjà infligés

	var base_time:      float = MineGenerator.get_mining_time(_target)
	var speed_bonus:    float = ResearchManager.get_mining_speed_bonus(
		GameManager.player_corporation
	)
	var effective_time: float = base_time / maxf(1.0 + speed_bonus, 0.1)

	_progress += delta / effective_time
	_block_progress[_target] = _progress   # mémorise la "vie" du bloc
	mine_target_changed.emit(_target, _progress)

	if _progress >= 1.0:
		_break(_target)

func _reset() -> void:
	if _target != Vector2i(-999, -999):
		_target   = Vector2i(-999, -999)
		_progress = 0.0
		mine_target_changed.emit(_target, 0.0)

func _break(tile_pos: Vector2i) -> void:
	_block_progress.erase(tile_pos)
	var resource: String = MineGenerator.get_resource(tile_pos)
	var amount:   int    = MineGenerator.get_yield(tile_pos)

	MineGenerator.remove_tile(tile_pos)

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

# Blocs partiellement minés (Vector2i -> progression 0..1), pour dessiner les craquelures.
func get_damaged_blocks() -> Dictionary:
	return _block_progress

func _get_player_tile() -> Vector2i:
	return Vector2i(
		floori(_body.global_position.x / TILE_SIZE),
		floori(_body.global_position.y / TILE_SIZE)
	)

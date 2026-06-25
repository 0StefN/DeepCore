extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
#  World.gd — Scene setup and signal wiring.
#
#  Two TileMapLayers:
#  - SurfaceTileLayer : hand-painted in editor, only shaft hole carved at runtime.
#  - MineTileLayer    : procedurally generated, never edited in editor.
#
#  Markers drive generation config (move in editor, no code change needed):
#  - MineStart   : Y position → where the mine begins (surface_height)
#  - ShaftCenter : X position → where the shaft hole is carved
# ─────────────────────────────────────────────────────────────────────────────

const TILE_SIZE: int = 32

const DROP_SCENE: PackedScene = preload("res://scenes/Level/ResourceDrop.tscn")

@onready var surface_tiles: TileMapLayer    = $SurfaceTileLayer
@onready var mine_tiles:    TileMapLayer    = $MineTileLayer
@onready var chest:         Chest           = $Chest
@onready var player:        CharacterBody2D = $Player
@onready var overlay:       Node2D          = $Overlay
@onready var day_timer:     Node            = $DayTimer
@onready var mine_hud:      CanvasLayer     = $MineHUD
@onready var mine_start:    Marker2D        = $MineStart
@onready var shaft_center:  Marker2D        = $ShaftCenter

var _drops: Node2D = null   # runtime container for ResourceDrop nodes

func _ready() -> void:
	if not GameManager.player_corporation:
		GameManager.start_game("Debug Corp")

	# ── Mine generation (one mine = one parcel) ───────────────────────────────
	var parcels: Array[ParcelData] = GameManager.player_corporation.owned_parcels
	if parcels.is_empty():
		# Debug fallback: pick the first non-public parcel of the day
		if GameManager.current_parcels.is_empty():
			GameManager.current_parcels = ParcelGenerator.generate_parcels(1)
		var debug_parcel: ParcelData = GameManager.current_parcels[0]
		for p in GameManager.current_parcels:
			if not p.is_public:
				debug_parcel = p
				break
		var single: Array[ParcelData] = [debug_parcel]
		parcels = single

	# ── Configure generator from markers ─────────────────────────────────────
	MineGenerator.surface_height = int(mine_start.position.y / TILE_SIZE)
	var shaft_x: int = int(shaft_center.position.x / TILE_SIZE)
	MineGenerator.shaft_center_x = shaft_x if shaft_x > 0 else -1

	MineGenerator.generate(parcels)
	MineGenerator.populate_tilemap(mine_tiles)
	LightManager.compute_all()

	# ── Carve shaft in hand-painted surface ───────────────────────────────────
	_carve_shaft()

	# ── Player setup ──────────────────────────────────────────────────────────
	player.global_position = MineGenerator.get_spawn_position(TILE_SIZE)

	var mining:    Node = player.get_node("MiningComponent")
	var inventory: Node = player.get_node("InventoryManager")
	mining.tile_layer = mine_tiles

	# ── Drops container (rendered below the darkness Overlay) ─────────────────
	_drops = Node2D.new()
	_drops.name = "Drops"
	add_child(_drops)
	move_child(_drops, overlay.get_index())

	# ── Signal wiring ─────────────────────────────────────────────────────────
	mining.drop_spawned.connect(_on_drop_spawned)
	mining.tile_broken.connect(LightManager.update_around)
	mining.mine_target_changed.connect(overlay._on_mine_target_changed)

	# ── Chest ─────────────────────────────────────────────────────────────────
	# Position is set manually in the scene editor — do not override it here.
	chest.deposit_triggered.connect(mine_hud.on_deposit_triggered)

	# ── HUD & timer ───────────────────────────────────────────────────────────
	mine_hud.setup(inventory, day_timer)
	day_timer.start()
	day_timer.time_expired.connect(_on_day_expired)

# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────

func _on_drop_spawned(resource: String, amount: int, world_pos: Vector2) -> void:
	var drop: ResourceDrop = DROP_SCENE.instantiate()
	_drops.add_child(drop)
	drop.global_position = world_pos
	drop.setup(resource, amount, player, player.get_node("InventoryManager"))

func _carve_shaft() -> void:
	var shaft_left: int = MineGenerator.get_shaft_left()
	for x in range(shaft_left, shaft_left + MineGenerator.SHAFT_WIDTH):
		surface_tiles.erase_cell(Vector2i(x, MineGenerator.surface_height - 1))

func _on_day_expired() -> void:
	# Fin de la mine → phase du soir (vente, stockage, R&D)
	get_tree().change_scene_to_file.call_deferred("res://scenes/UI/EveningUI.tscn")

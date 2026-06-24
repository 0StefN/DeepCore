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

@onready var surface_tiles: TileMapLayer    = $SurfaceTileLayer
@onready var mine_tiles:    TileMapLayer    = $MineTileLayer
@onready var chest:         Chest           = $Chest
@onready var player:        CharacterBody2D = $Player
@onready var overlay:       Node2D          = $Overlay
@onready var day_timer:     Node            = $DayTimer
@onready var mine_hud:      CanvasLayer     = $MineHUD
@onready var mine_start:    Marker2D        = $MineStart
@onready var shaft_center:  Marker2D        = $ShaftCenter

func _ready() -> void:
	if not GameManager.player_corporation:
		GameManager.start_game("Debug Corp")

	# ── Mine generation ───────────────────────────────────────────────────────
	var parcels: Array[ParcelData] = GameManager.player_corporation.owned_parcels
	if parcels.is_empty():
		if GameManager.current_parcels.is_empty():
			GameManager.current_parcels = ParcelGenerator.generate_parcels(1)
		parcels = GameManager.current_parcels.slice(0, 3)

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

	# ── Signal wiring ─────────────────────────────────────────────────────────
	mining.resource_mined.connect(inventory.try_add)
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

func _carve_shaft() -> void:
	var shaft_left: int = MineGenerator.get_shaft_left()
	for x in range(shaft_left, shaft_left + MineGenerator.SHAFT_WIDTH):
		surface_tiles.erase_cell(Vector2i(x, MineGenerator.surface_height - 1))

func _on_day_expired() -> void:
	GameManager.start_evening_phase()
	get_tree().change_scene_to_file.call_deferred("res://scenes/UI/BiddingUI.tscn")

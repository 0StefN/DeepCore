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
@onready var ore_tiles:     TileMapLayer    = $MineOreLayer
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
	MineGenerator.populate_tilemap(mine_tiles, ore_tiles)
	LightManager.compute_all()

	# ── Carve shaft in hand-painted surface ───────────────────────────────────
	_carve_shaft()

	# ── Player setup ──────────────────────────────────────────────────────────
	player.global_position = MineGenerator.get_spawn_position(TILE_SIZE)

	var mining:    Node = player.get_node("MiningComponent")
	var inventory: Node = player.get_node("InventoryManager")

	# ── Drops container (rendered below the darkness Overlay) ─────────────────
	_drops = Node2D.new()
	_drops.name = "Drops"
	add_child(_drops)
	move_child(_drops, overlay.get_index())

	# ── Signal wiring ─────────────────────────────────────────────────────────
	mining.drop_spawned.connect(_on_drop_spawned)
	mining.tile_broken.connect(LightManager.update_around)
	mining.mine_target_changed.connect(overlay._on_mine_target_changed)
	mining.torch_placed.connect(overlay.add_torch)
	mining.dynamite_placed.connect(_on_dynamite_placed)

	# ── Chest ─────────────────────────────────────────────────────────────────
	# Position is set manually in the scene editor — do not override it here.
	chest.deposit_triggered.connect(mine_hud.on_deposit_triggered)

	# ── HUD & timer ───────────────────────────────────────────────────────────
	mine_hud.setup(inventory, day_timer)
	mine_hud.bind_jetpack(player.get_node("JetpackComponent"))
	mine_hud.bind_tools(mining)
	mine_hud.manual_drop.connect(_on_manual_drop)
	day_timer.start()
	day_timer.time_expired.connect(_on_day_expired)

# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────

func _on_drop_spawned(resource: String, amount: int, world_pos: Vector2) -> void:
	var drop: ResourceDrop = DROP_SCENE.instantiate()
	_drops.add_child(drop)
	drop.global_position = world_pos
	drop.setup(resource, amount, player, player.get_node("InventoryManager"))

func _on_manual_drop(resource: String) -> void:
	var inv: Node = player.get_node("InventoryManager")
	if not inv.remove_one(resource):
		return
	var drop: ResourceDrop = DROP_SCENE.instantiate()
	_drops.add_child(drop)
	drop.global_position = player.global_position + Vector2(randf_range(-6.0, 6.0), -4.0)
	drop.setup(resource, 1, player, inv, 3.0)   # 3s avant que l'aimant puisse le reprendre

# ─── Dynamite ─────────────────────────────────────────────────────────────────

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(
		float(tile.x) * TILE_SIZE + TILE_SIZE * 0.5,
		float(tile.y) * TILE_SIZE + TILE_SIZE * 0.5
	)

func _on_dynamite_placed(tile: Vector2i) -> void:
	var corp: CorporationData = GameManager.player_corporation
	var radius: float = maxf(1.0, ResearchManager.get_effect("explosives_radius", corp))
	var dyn := Dynamite.new()
	add_child(dyn)
	dyn.global_position = _tile_center(tile)
	dyn.setup(radius)
	dyn.detonated.connect(_on_dynamite_detonated.bind(tile, radius))

func _on_dynamite_detonated(center: Vector2i, radius: float) -> void:
	var r: int = int(ceil(radius))
	var r2: float = radius * radius
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if float(dx * dx + dy * dy) > r2:
				continue
			var tile: Vector2i = center + Vector2i(dx, dy)
			if not MineGenerator.is_solid(tile) or MineGenerator.is_bedrock(tile):
				continue
			var resource: String = MineGenerator.get_resource(tile)
			var amount:   int    = MineGenerator.get_yield(tile)
			MineGenerator.remove_tile(tile)
			LightManager.update_around(tile)
			if resource != "":
				_on_drop_spawned(resource, amount, _tile_center(tile))

func _carve_shaft() -> void:
	var shaft_left: int = MineGenerator.get_shaft_left()
	for x in range(shaft_left, shaft_left + MineGenerator.SHAFT_WIDTH):
		surface_tiles.erase_cell(Vector2i(x, MineGenerator.surface_height - 1))

func _on_day_expired() -> void:
	# Fin de la mine → phase du soir (vente, stockage, R&D)
	get_tree().change_scene_to_file.call_deferred("res://scenes/UI/EveningUI.tscn")

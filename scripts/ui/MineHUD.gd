extends CanvasLayer

# ─────────────────────────────────────────────────────────────────────────────
#  MineHUD.gd
#  In-mine HUD: timer, inventory slots, bag-full warning, deposit feedback.
#
#  Scene structure (MineHUD.tscn):
#  MineHUD (CanvasLayer, layer = 10)
#  └── Root (Control, Full Rect)
#      ├── TopBar (HBoxContainer, anchor top)
#      │   ├── TimerLabel    (Label)
#      │   └── ChestLabel    (Label)
#      ├── BagFullLabel      (Label, anchor center)
#      ├── DepositLabel      (Label, anchor center-bottom)
#      └── SlotsContainer    (HBoxContainer, anchor bottom-left)
# ─────────────────────────────────────────────────────────────────────────────

# ─── Resource display helpers ─────────────────────────────────────────────────
const RESOURCE_ICONS: Dictionary = {
	"coal":    "⛏",
	"iron":    "⚙",
	"gold":    "✦",
	"gem":     "◆",
	"crystal": "✧",
}

@onready var timer_label:     Label         = $Root/TopBar/TimerLabel
@onready var chest_label:     Label         = $Root/TopBar/ChestLabel
@onready var bag_full_label:  Label         = $Root/BagFullLabel
@onready var deposit_label:   Label         = $Root/DepositLabel
@onready var slots_container: HBoxContainer = $Root/SlotsContainer
@onready var fuel_gauge:      VBoxContainer = $Root/FuelGauge
@onready var fuel_bar:        ProgressBar   = $Root/FuelGauge/FuelBar
@onready var hotbar:          HBoxContainer = $Root/Hotbar

var _inventory: Node  = null
var _day_timer: Node  = null
var _slot_panels: Array[Panel] = []

var _bag_full_timer:  float = 0.0   # seconds to show "bag full" warning
var _deposit_timer:   float = 0.0   # seconds to show deposit feedback

# ─── Barre d'objets (hotbar) & menu d'inventaire ──────────────────────────────
signal manual_drop(resource: String)

const TOOL_DEFS: Array = [
	{ "name": "Pioche", "icon": "⛏", "consumable": "" },
	{ "name": "Torche", "icon": "🔦", "consumable": "torch" },
	{ "name": "Dynamite", "icon": "🧨", "consumable": "dynamite" },
]

var _mining: Node = null
var _hotbar_panels: Array[PanelContainer] = []
var _hotbar_labels: Array[Label] = []
var _inv_menu: Control = null

# ─────────────────────────────────────────────────────────────────────────────

func setup(inventory: Node, day_timer: Node) -> void:
	_inventory = inventory
	_day_timer = day_timer

	inventory.inventory_changed.connect(_on_inventory_changed)
	inventory.inventory_full.connect(_on_inventory_full)
	day_timer.time_updated.connect(_on_time_updated)

	_build_slot_displays()
	_refresh_slots()
	_refresh_chest()

	bag_full_label.visible  = false
	deposit_label.visible   = false

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_inventory"):
		_toggle_inventory()

	# Bag full warning countdown
	if _bag_full_timer > 0.0:
		_bag_full_timer -= delta
		if _bag_full_timer <= 0.0:
			bag_full_label.hide()

	# Deposit feedback countdown
	if _deposit_timer > 0.0:
		_deposit_timer -= delta
		if _deposit_timer <= 0.0:
			deposit_label.hide()

	# Flash bag full label
	if bag_full_label.visible:
		var alpha: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		bag_full_label.modulate = Color(1.0, 0.3, 0.3, alpha)

# ─────────────────────────────────────────────────────────────────────────────
#  SLOT DISPLAY
# ─────────────────────────────────────────────────────────────────────────────

func _build_slot_displays() -> void:
	for child in slots_container.get_children():
		child.queue_free()
	_slot_panels.clear()

	for _i in _inventory.slot_count:
		var sq := Panel.new()
		sq.custom_minimum_size = Vector2(24, 24)
		sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slots_container.add_child(sq)
		_slot_panels.append(sq)

# Représentation minimaliste : case vide (hollow), pleine de place (blanc), pleine (rouge).
func _refresh_slots() -> void:
	if not _inventory:
		return
	for i in _slot_panels.size():
		if i >= _inventory.slots.size():
			break
		var slot: Dictionary = _inventory.slots[i]
		var kind: int
		if slot["resource"] == "" or slot["amount"] <= 0:
			kind = 0
		elif slot["amount"] >= _inventory.stack_size:
			kind = 2
		else:
			kind = 1
		_slot_panels[i].add_theme_stylebox_override("panel", _slot_square_style(kind))

# 0 = vide (contour blanc, fond transparent) ; 1 = occupée avec place (blanc) ; 2 = pleine (rouge).
func _slot_square_style(kind: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left     = 3
	sb.corner_radius_top_right    = 3
	sb.corner_radius_bottom_left  = 3
	sb.corner_radius_bottom_right = 3
	match kind:
		2:
			sb.bg_color     = Color(0.85, 0.22, 0.22, 0.92)
			sb.border_color = Color(1.0, 0.5, 0.5, 0.95)
		1:
			sb.bg_color     = Color(0.95, 0.95, 0.97, 0.9)
			sb.border_color = Color(1.0, 1.0, 1.0, 0.95)
		_:
			sb.bg_color     = Color(1.0, 1.0, 1.0, 0.0)
			sb.border_color = Color(1.0, 1.0, 1.0, 0.65)
	return sb

func _refresh_chest() -> void:
	if not GameManager.player_corporation:
		return
	var inv: Dictionary = GameManager.player_corporation.inventory
	var parts: Array[String] = []
	for res in inv:
		if inv[res] > 0:
			var icon: String = RESOURCE_ICONS.get(res, "◆")
			parts.append("%s %d" % [icon, inv[res]])
	chest_label.text = "Chest: " + (", ".join(parts) if not parts.is_empty() else "empty")

# ─────────────────────────────────────────────────────────────────────────────
#  SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────────────────────

func _on_inventory_changed() -> void:
	_refresh_slots()
	_refresh_chest()
	if _inv_menu and is_instance_valid(_inv_menu):
		_rebuild_inv_menu()

func _on_inventory_full() -> void:
	bag_full_label.text = "⚠ Bag full — return to surface!"
	bag_full_label.show()
	_bag_full_timer = 3.0

func _on_time_updated(seconds_left: float) -> void:
	timer_label.text = _day_timer.get_formatted()
	# Turn red when under 30 seconds
	if seconds_left <= 30.0:
		timer_label.modulate = Color(1.0, 0.3 + seconds_left / 45.0, 0.2)
	else:
		timer_label.modulate = Color.WHITE

func on_deposit_triggered(total_units: int) -> void:
	deposit_label.text    = "✓ Deposited %d units!" % total_units
	deposit_label.show()
	_deposit_timer = 2.5
	_refresh_chest()

# ─────────────────────────────────────────────────────────────────────────────
#  JETPACK — jauge de carburant (affichée seulement si le jetpack est débloqué)
# ─────────────────────────────────────────────────────────────────────────────

func bind_jetpack(jetpack: Node) -> void:
	if not jetpack or not jetpack.enabled:
		fuel_gauge.visible = false
		return
	fuel_gauge.visible = true
	jetpack.fuel_changed.connect(_on_fuel_changed)
	_on_fuel_changed(jetpack.fuel_ratio(), false)

func _on_fuel_changed(ratio: float, active: bool) -> void:
	if not fuel_bar:
		return
	fuel_bar.value = ratio
	# Vert (plein) → rouge (vide) ; légèrement éclairci pendant la poussée.
	var col := Color(1.0 - ratio, 0.35 + ratio * 0.55, 0.2)
	fuel_bar.modulate = col.lightened(0.2) if active else col

# ─────────────────────────────────────────────────────────────────────────────
#  BARRE D'OBJETS (hotbar)
# ─────────────────────────────────────────────────────────────────────────────

func bind_tools(mining: Node) -> void:
	_mining = mining
	mining.tool_changed.connect(_on_tool_changed)
	mining.torch_placed.connect(_on_torch_placed)
	_build_hotbar()

func _build_hotbar() -> void:
	for c in hotbar.get_children():
		c.queue_free()
	_hotbar_panels.clear()
	_hotbar_labels.clear()
	for _i in TOOL_DEFS.size():
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(88, 58)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(label)
		hotbar.add_child(panel)
		_hotbar_panels.append(panel)
		_hotbar_labels.append(label)
	_refresh_hotbar()

func _refresh_hotbar() -> void:
	if _hotbar_labels.is_empty():
		return
	var corp: CorporationData = GameManager.player_corporation
	for i in TOOL_DEFS.size():
		var def: Dictionary = TOOL_DEFS[i]
		var is_consumable: bool = def["consumable"] != ""
		var cnt: int = corp.consumable_count(def["consumable"]) if (is_consumable and corp) else 0
		# Slot consommable masqué tant qu'on n'en possède pas.
		if is_consumable:
			_hotbar_panels[i].visible = cnt > 0
		var txt: String = "[%d] %s\n%s" % [i + 1, def["icon"], def["name"]]
		if is_consumable:
			txt += "  ×%d" % cnt
		_hotbar_labels[i].text = txt
		var selected: bool = (_mining != null and _mining.selected_tool == i)
		_hotbar_panels[i].modulate = Color(1, 1, 1, 1) if selected else Color(0.55, 0.55, 0.6, 0.8)

func _on_tool_changed(_index: int) -> void:
	_refresh_hotbar()

func _on_torch_placed(_tile: Vector2i) -> void:
	_refresh_hotbar()   # le compteur de torches a baissé

# ─────────────────────────────────────────────────────────────────────────────
#  MENU D'INVENTAIRE (Tab) — clic droit sur une ressource pour la lâcher
# ─────────────────────────────────────────────────────────────────────────────

func _toggle_inventory() -> void:
	if _inv_menu and is_instance_valid(_inv_menu):
		_inv_menu.queue_free()
		_inv_menu = null
		return
	_build_inv_menu()

func _rebuild_inv_menu() -> void:
	if _inv_menu and is_instance_valid(_inv_menu):
		_inv_menu.queue_free()
	_inv_menu = null
	_build_inv_menu()

func _build_inv_menu() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	$Root.add_child(backdrop)
	_inv_menu = backdrop

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(380, 0)
	backdrop.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Inventaire — clic droit sur une case pour la lâcher"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	if _inventory:
		for i in _inventory.slot_count:
			var slot: Dictionary = _inventory.slots[i] if i < _inventory.slots.size() \
				else { "resource": "", "amount": 0 }
			var filled: bool = slot["resource"] != "" and slot["amount"] > 0

			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(76, 76)
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.add_theme_stylebox_override("panel", _inv_cell_style(filled))

			var cl := Label.new()
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			if filled:
				cl.text = "%s\n×%d" % [RESOURCE_ICONS.get(slot["resource"], "◆"), slot["amount"]]
				cell.gui_input.connect(_on_inv_cell_input.bind(str(slot["resource"])))
			cell.add_child(cl)
			grid.add_child(cell)

	var hint := Label.new()
	hint.text = "Tab pour fermer"
	hint.modulate = Color(0.6, 0.6, 0.6)
	box.add_child(hint)

func _inv_cell_style(filled: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left     = 4
	sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_left  = 4
	sb.corner_radius_bottom_right = 4
	sb.bg_color     = Color(1, 1, 1, 0.10) if filled else Color(1, 1, 1, 0.03)
	sb.border_color = Color(1, 1, 1, 0.45) if filled else Color(1, 1, 1, 0.15)
	return sb

func _on_inv_cell_input(event: InputEvent, resource: String) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		manual_drop.emit(resource)   # World retire du sac + spawn le drop ; le menu se rebuild

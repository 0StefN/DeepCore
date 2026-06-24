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

var _inventory: Node  = null
var _day_timer: Node  = null
var _slot_labels: Array[Label] = []

var _bag_full_timer:  float = 0.0   # seconds to show "bag full" warning
var _deposit_timer:   float = 0.0   # seconds to show deposit feedback

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
	_slot_labels.clear()

	for i in _inventory.slot_count:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(90, 60)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode        = TextServer.AUTOWRAP_WORD

		panel.add_child(label)
		slots_container.add_child(panel)
		_slot_labels.append(label)

func _refresh_slots() -> void:
	if not _inventory:
		return
	for i in _slot_labels.size():
		var label: Label = _slot_labels[i]
		if i >= _inventory.slots.size():
			break
		var slot: Dictionary = _inventory.slots[i]
		if slot["resource"] == "":
			label.text = "[ empty ]"
			label.modulate = Color(0.5, 0.5, 0.5)
		else:
			var icon: String = RESOURCE_ICONS.get(slot["resource"], "?")
			label.text = "%s\n%s\n%d / %d" % [
				icon,
				slot["resource"].capitalize(),
				slot["amount"],
				_inventory.stack_size
			]
			# Color based on fullness
			var fill: float = float(slot["amount"]) / float(_inventory.stack_size)
			label.modulate = Color(1.0, 1.0 - fill * 0.5, 1.0 - fill * 0.8)

func _refresh_chest() -> void:
	if not GameManager.player_corporation:
		return
	var inv: Dictionary = GameManager.player_corporation.inventory
	var parts: Array[String] = []
	for res in inv:
		if inv[res] > 0:
			var icon: String = RESOURCE_ICONS.get(res, "?")
			parts.append("%s %d" % [icon, inv[res]])
	chest_label.text = "Chest: " + (", ".join(parts) if not parts.is_empty() else "empty")

# ─────────────────────────────────────────────────────────────────────────────
#  SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────────────────────

func _on_inventory_changed() -> void:
	_refresh_slots()
	_refresh_chest()

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

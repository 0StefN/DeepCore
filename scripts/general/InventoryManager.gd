extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  InventoryManager.gd
#  Manages the player's carried bag (slots + stacks).
#  Only resources deposited at the chest count toward end-of-day sales.
#
#  Slot system:
#  - Each slot holds one resource type, up to stack_size units.
#  - slot_count and stack_size are both upgradeable via research.
# ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_SLOT_COUNT: int = 3
const DEFAULT_STACK_SIZE: int = 8

var slot_count: int = DEFAULT_SLOT_COUNT
var stack_size: int = DEFAULT_STACK_SIZE

# Slot format: { "resource": String, "amount": int }
# Empty slot:  { "resource": "",     "amount": 0   }
var slots: Array[Dictionary] = []

signal inventory_changed()
signal inventory_full()                                    # fired when try_add fails
signal resource_deposited(resource: String, amount: int)   # fired per slot on deposit

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_apply_research_bonuses()
	_init_slots()

# Applique les bonus de recherche (Sac Renforcé → piles, Cases Supplémentaires → cases).
func _apply_research_bonuses() -> void:
	var corp: CorporationData = GameManager.player_corporation
	if corp == null:
		return
	slot_count = DEFAULT_SLOT_COUNT + int(ResearchManager.get_effect("slot_bonus", corp))
	stack_size = DEFAULT_STACK_SIZE + int(ResearchManager.get_effect("stack_bonus", corp))

func _init_slots() -> void:
	slots.clear()
	for _i in slot_count:
		slots.append({ "resource": "", "amount": 0 })

# ─────────────────────────────────────────────────────────────────────────────
#  CORE OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────

# Try to add one unit of a resource to the bag.
# Returns true on success, false if the bag is full.
func try_add(resource: String) -> bool:
	# 1 — Existing slot of the same type with room left
	for slot in slots:
		if slot["resource"] == resource and slot["amount"] < stack_size:
			slot["amount"] += 1
			inventory_changed.emit()
			return true

	# 2 — Empty slot
	for slot in slots:
		if slot["resource"] == "":
			slot["resource"] = resource
			slot["amount"]   = 1
			inventory_changed.emit()
			return true

	# 3 — Bag is full
	inventory_full.emit()
	return false

# Empty all slots into the corporation chest.
func deposit_all() -> void:
	var deposited: bool = false
	for slot in slots:
		if slot["resource"] != "" and slot["amount"] > 0:
			GameManager.player_corporation.add_resource(slot["resource"], slot["amount"])
			resource_deposited.emit(slot["resource"], slot["amount"])
			slot["resource"] = ""
			slot["amount"]   = 0
			deposited        = true
	if deposited:
		inventory_changed.emit()

# Retire une unité de la ressource donnée (drop manuel). Renvoie true si retiré.
func remove_one(resource: String) -> bool:
	for slot in slots:
		if slot["resource"] == resource and slot["amount"] > 0:
			slot["amount"] -= 1
			if slot["amount"] <= 0:
				slot["resource"] = ""
			inventory_changed.emit()
			return true
	return false

# ─────────────────────────────────────────────────────────────────────────────
#  QUERIES
# ─────────────────────────────────────────────────────────────────────────────

func is_full() -> bool:
	for slot in slots:
		if slot["resource"] == "" or slot["amount"] < stack_size:
			return false
	return true

func is_empty() -> bool:
	for slot in slots:
		if slot["amount"] > 0:
			return false
	return true

func get_total_units() -> int:
	var total: int = 0
	for slot in slots:
		total += slot["amount"]
	return total

func get_capacity() -> int:
	return slot_count * stack_size

# ─────────────────────────────────────────────────────────────────────────────
#  UPGRADES (called by ResearchManager)
# ─────────────────────────────────────────────────────────────────────────────

func upgrade_slot_count(new_count: int) -> void:
	slot_count = new_count
	while slots.size() < slot_count:
		slots.append({ "resource": "", "amount": 0 })
	inventory_changed.emit()

func upgrade_stack_size(new_size: int) -> void:
	stack_size = new_size
	inventory_changed.emit()

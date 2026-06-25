class_name Chest
extends Area2D

# ─────────────────────────────────────────────────────────────────────────────
#  Chest.gd
#  Surface chest. The player deposits their bag by pressing E while standing
#  next to it. The "Press E" prompt only shows while the player is in range.
#  Visuals are handled by the Sprite2D child in Chest.tscn.
# ─────────────────────────────────────────────────────────────────────────────

signal deposit_triggered(total_units: int)

@onready var prompt: Label = $InterractionPrompt

var _inventory: Node = null   # set while a player body is in range

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if prompt:
		prompt.hide()

func _unhandled_input(event: InputEvent) -> void:
	if _inventory == null:
		return
	if event.is_action_pressed("interact"):
		_deposit()

func _on_body_entered(body: Node) -> void:
	if not body is CharacterBody2D:
		return
	var inv: Node = body.get_node_or_null("InventoryManager")
	if not inv:
		return
	_inventory = inv
	if prompt:
		prompt.show()

func _on_body_exited(body: Node) -> void:
	if not body is CharacterBody2D:
		return
	if body.get_node_or_null("InventoryManager") == _inventory:
		_inventory = null
		if prompt:
			prompt.hide()

func _deposit() -> void:
	if _inventory == null or _inventory.is_empty():
		return
	var total: int = _inventory.get_total_units()
	_inventory.deposit_all()
	deposit_triggered.emit(total)
	play_deposit_animation()

func play_deposit_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.6, 1.4, 0.3), 0.08)
	tween.tween_property(self, "modulate", Color.WHITE,           0.45)

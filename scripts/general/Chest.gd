class_name Chest
extends Area2D

# ─────────────────────────────────────────────────────────────────────────────
#  Chest.gd
#  Deposit logic + feedback animation for the surface chest.
#  Visuals are handled by the Sprite2D child in Chest.tscn.
# ─────────────────────────────────────────────────────────────────────────────

signal deposit_triggered(total_units: int)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body is CharacterBody2D:
		return
	var inventory: Node = body.get_node_or_null("InventoryManager")
	if not inventory or inventory.is_empty():
		return
	var total: int = inventory.get_total_units()
	inventory.deposit_all()
	deposit_triggered.emit(total)
	play_deposit_animation()

func play_deposit_animation() -> void:
	# Flash the sprite by tweening modulate — works with any child Sprite2D
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.6, 1.4, 0.3), 0.08)
	tween.tween_property(self, "modulate", Color.WHITE,           0.45)

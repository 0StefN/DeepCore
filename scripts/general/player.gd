extends CharacterBody2D

# ─────────────────────────────────────────────────────────────────────────────
#  Player.gd  —  Movement only.
#  All other gameplay systems live in child components.
# ─────────────────────────────────────────────────────────────────────────────

const SPEED:         float = 160.0
const JUMP_VELOCITY: float = -400.0
const GRAVITY:       float = 950.0
const PLAYER_HEIGHT: int   = 28

@onready var inventory:  Node = $InventoryManager
@onready var mining:     Node = $MiningComponent

func _draw() -> void:
	draw_rect(Rect2(-10, -PLAYER_HEIGHT, 20, PLAYER_HEIGHT), Color(0.95, 0.85, 0.1))
	draw_rect(Rect2(-7,  -PLAYER_HEIGHT + 5, 4, 4), Color.BLACK)
	draw_rect(Rect2( 3,  -PLAYER_HEIGHT + 5, 4, 4), Color.BLACK)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var dir: float = Input.get_axis("left", "right")
	velocity.x = dir * SPEED if dir != 0.0 else move_toward(velocity.x, 0.0, SPEED)

	move_and_slide()
	queue_redraw()

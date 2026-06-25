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

# Valeurs effectives, modifiées par la recherche (Bottes / Saut amélioré)
var _speed:         float = SPEED
var _jump_velocity: float = JUMP_VELOCITY

func _ready() -> void:
	var corp: CorporationData = GameManager.player_corporation
	if corp:
		_speed         = SPEED * (1.0 + ResearchManager.get_effect("move_speed", corp))
		_jump_velocity = JUMP_VELOCITY * (1.0 + ResearchManager.get_effect("jump_power", corp))

func _draw() -> void:
	draw_rect(Rect2(-10, -PLAYER_HEIGHT, 20, PLAYER_HEIGHT), Color(0.95, 0.85, 0.1))
	draw_rect(Rect2(-7,  -PLAYER_HEIGHT + 5, 4, 4), Color.BLACK)
	draw_rect(Rect2( 3,  -PLAYER_HEIGHT + 5, 4, 4), Color.BLACK)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = _jump_velocity

	var dir: float = Input.get_axis("left", "right")
	velocity.x = dir * _speed if dir != 0.0 else move_toward(velocity.x, 0.0, _speed)

	move_and_slide()
	queue_redraw()

extends CharacterBody2D

# ─────────────────────────────────────────────────────────────────────────────
#  Player.gd  —  Movement only.
#  All other gameplay systems live in child components.
#
#  Saut à HAUTEUR VARIABLE (« jump cut ») :
#    - Maintenir Saut → plein saut (~2,5 tuiles).
#    - Tap court      → petit saut (~1,25 tuile) : relâcher en pleine montée
#      plafonne la vitesse ascendante. La hauteur dépend donc de la durée d'appui.
#
#  Le saut est paramétré par HAUTEUR + TEMPS d'apex : on dérive la gravité de
#  MONTÉE de ces deux valeurs, séparément de la gravité de CHUTE (constante).
#  La recherche « Saut Amélioré » (jump_power) réduit le TEMPS d'apex → saut plus
#  vif, SANS changer les hauteurs (mini comme plein). Voir simulation d'équilibrage.
# ─────────────────────────────────────────────────────────────────────────────

const SPEED:         float = 160.0
const GRAVITY_FALL:  float = 950.0   # gravité de chute — indépendante de l'upgrade
const PLAYER_HEIGHT: int   = 28

# Saut paramétré (valeurs de base, sans upgrade) :
const JUMP_HEIGHT_FULL: float = 84.0   # px : apex en maintenant la touche (~2,5 tuiles)
const JUMP_HEIGHT_MIN:  float = 36.0   # px : apex d'un tap minimal       (~1,25 tuile)
const JUMP_TIME_APEX:   float = 0.40   # s  : temps pour atteindre l'apex (réduit par l'upgrade)

# Sonde de debug : imprime au spawn les valeurs effectives lues depuis la recherche.
# Mettre à false (ou supprimer le bloc dans _ready) une fois la vérification faite.
const DEBUG_STATS: bool = false

@onready var inventory:  Node = $InventoryManager
@onready var mining:     Node = $MiningComponent
@onready var jetpack:    Node = $JetpackComponent

# Valeurs effectives, dérivées en _ready (modifiées par la recherche).
var _speed:             float = SPEED
var _gravity_ascent:    float = GRAVITY_FALL   # gravité pendant la montée (dérivée du saut)
var _jump_velocity:     float = -420.0         # impulsion du plein saut (dérivée)
var _jump_cut_velocity: float = -275.0         # plancher de vitesse au relâchement (dérivé)

func _ready() -> void:
	var corp: CorporationData = GameManager.player_corporation
	var move_bonus: float = 0.0
	var snappy:     float = 0.0   # « Saut Amélioré » : vivacité (= temps d'apex plus court)
	if corp:
		move_bonus = ResearchManager.get_effect("move_speed", corp)
		snappy     = ResearchManager.get_effect("jump_power", corp)

	_speed = SPEED * (1.0 + move_bonus)

	# Temps d'apex raccourci par l'upgrade → saut plus vif, hauteurs inchangées.
	var t_apex: float = JUMP_TIME_APEX / (1.0 + snappy)
	_gravity_ascent    = 2.0 * JUMP_HEIGHT_FULL / (t_apex * t_apex)
	_jump_velocity     = -2.0 * JUMP_HEIGHT_FULL / t_apex
	_jump_cut_velocity = -sqrt(2.0 * _gravity_ascent * JUMP_HEIGHT_MIN)

	# ── Sonde de debug : confirme que la recherche est bien lue au spawn ──────
	if DEBUG_STATS:
		var corp_name: String = corp.corp_name if corp else "<aucune corpo>"
		var research: Dictionary = corp.research if corp else {}
		var mining_bonus: float = ResearchManager.get_effect("mining_speed", corp) if corp else 0.0
		print("[Player] corpo=%s | recherche=%s" % [corp_name, research])
		print("[Player]   vitesse=%.0f px/s (move_speed +%.0f%%)" % [_speed, move_bonus * 100.0])
		print("[Player]   saut: impulsion=%.0f, plancher_tap=%.0f, g_montée=%.0f (jump_power +%.0f%%)"
			% [_jump_velocity, _jump_cut_velocity, _gravity_ascent, snappy * 100.0])
		print("[Player]   minage: bonus vitesse +%.0f%%" % [mining_bonus * 100.0])

func _draw() -> void:
	draw_rect(Rect2(-10, -PLAYER_HEIGHT, 20, PLAYER_HEIGHT), Color(0.95, 0.85, 0.1))
	draw_rect(Rect2(-7,  -PLAYER_HEIGHT + 5, 4, 4), Color.BLACK)
	draw_rect(Rect2( 3,  -PLAYER_HEIGHT + 5, 4, 4), Color.BLACK)

func _physics_process(delta: float) -> void:
	# Gravité asymétrique : montée (dérivée de l'upgrade) vs chute (constante).
	if not is_on_floor():
		var g: float = _gravity_ascent if velocity.y < 0.0 else GRAVITY_FALL
		velocity.y += g * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = _jump_velocity

	# Saut variable : relâcher pendant la montée plafonne l'élan → saut plus court.
	if Input.is_action_just_released("jump") and velocity.y < _jump_cut_velocity:
		velocity.y = _jump_cut_velocity

	# Jetpack : maintenir "jump" en l'air pour voler (carburant se recharge au sol).
	velocity = jetpack.process_flight(velocity, delta, is_on_floor(), Input.is_action_pressed("jump"))

	var dir: float = Input.get_axis("left", "right")
	velocity.x = dir * _speed if dir != 0.0 else move_toward(velocity.x, 0.0, _speed)

	move_and_slide()
	queue_redraw()

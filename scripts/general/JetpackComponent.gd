extends Node
class_name JetpackComponent

# ─────────────────────────────────────────────────────────────────────────────
#  JetpackComponent.gd
#  Logique de vol du jetpack. Module piloté par player.gd : ce composant ne
#  bouge pas le joueur lui-même, il modifie la vélocité qu'on lui passe.
#
#  Débloqué via la recherche "jetpack". Chemin d'upgrades :
#    jetpack_fuel     → autonomie (capacité de carburant)
#    jetpack_thrust   → poussée + vitesse de montée
#    jetpack_recharge → vitesse de recharge au sol
#
#  Commande : maintenir "jump" (Espace) EN L'AIR pour voler.
#  Le carburant se recharge UNIQUEMENT au sol.
# ─────────────────────────────────────────────────────────────────────────────

const THRUST_ACCEL_BASE:   float = 2400.0  # accélération de poussée vers le haut (px/s²)
const MAX_RISE_SPEED_BASE: float = 300.0   # vitesse de montée plafonnée (px/s)
const FUEL_MAX_BASE:       float = 1.4     # autonomie de base (s de poussée)
const RECHARGE_BASE:       float = 0.6     # s de carburant rendues / s au sol
const DRAIN_RATE:          float = 1.0     # s de carburant consommées / s en vol

signal fuel_changed(ratio: float, active: bool)

var enabled:        bool  = false
var max_fuel:       float = FUEL_MAX_BASE
var fuel:           float = FUEL_MAX_BASE
var thrust_accel:   float = THRUST_ACCEL_BASE
var max_rise_speed: float = MAX_RISE_SPEED_BASE
var recharge_rate:  float = RECHARGE_BASE

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	var corp: CorporationData = GameManager.player_corporation
	if not corp:
		return
	enabled = corp.has_research("jetpack")

	var fuel_bonus:     float = ResearchManager.get_effect("jetpack_fuel", corp)
	var thrust_bonus:   float = ResearchManager.get_effect("jetpack_thrust", corp)
	var recharge_bonus: float = ResearchManager.get_effect("jetpack_recharge", corp)

	max_fuel       = FUEL_MAX_BASE       * (1.0 + fuel_bonus)
	thrust_accel   = THRUST_ACCEL_BASE   * (1.0 + thrust_bonus)
	max_rise_speed = MAX_RISE_SPEED_BASE * (1.0 + thrust_bonus)
	recharge_rate  = RECHARGE_BASE       * (1.0 + recharge_bonus)
	fuel = max_fuel

# Appelé par player.gd dans _physics_process, APRÈS l'application de la gravité
# et AVANT move_and_slide(). Retourne la vélocité (éventuellement modifiée).
func process_flight(velocity: Vector2, delta: float, on_floor: bool, thrust_held: bool) -> Vector2:
	if not enabled:
		return velocity

	var active: bool = false

	if on_floor:
		# Recharge uniquement au sol.
		if fuel < max_fuel:
			fuel = minf(max_fuel, fuel + recharge_rate * delta)
	elif thrust_held and fuel > 0.0:
		# Poussée vers le haut (y négatif = haut), vitesse de montée plafonnée.
		velocity.y -= thrust_accel * delta
		if velocity.y < -max_rise_speed:
			velocity.y = -max_rise_speed
		fuel = maxf(0.0, fuel - DRAIN_RATE * delta)
		active = true

	fuel_changed.emit(fuel_ratio(), active)
	return velocity

func fuel_ratio() -> float:
	return fuel / max_fuel if max_fuel > 0.0 else 0.0

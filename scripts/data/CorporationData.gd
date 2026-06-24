class_name CorporationData
extends Resource

# ─────────────────────────────────────────────────────────────────────────────
#  CorporationData.gd
#  Représente une corporation — joueur ou IA.
#  Stocke l'argent, l'inventaire, la recherche et les parcelles du jour.
# ─────────────────────────────────────────────────────────────────────────────

enum Personality {
	AGGRESSIVE,    # Surpaye les parcelles profondes et riches
	OPPORTUNIST,   # Cible les mystères et les bonnes affaires
	CONSERVATIVE,  # Mises prudentes, évite les risques
	TECHNO,        # Cible les parcelles réservées dès qu'elle a la R&D
}

# ─── Identité ────────────────────────────────────────────────────────────────
@export var corp_id: int = 0
@export var corp_name: String = "Unknown Corp"
@export var color: Color = Color.WHITE
@export var is_player: bool = false
@export var personality: Personality = Personality.CONSERVATIVE

# ─── Finances ────────────────────────────────────────────────────────────────
@export var money: int = 1000

# ─── Inventaire (reset chaque jour après vente) ───────────────────────────────
var inventory: Dictionary = {
	"coal":    0,
	"iron":    0,
	"gold":    0,
	"gem":     0,
	"crystal": 0,
}

# ─── Recherche : clé = research_id, valeur = niveau (0 = non recherché) ──────
var research: Dictionary = {}

# ─── Parcelles remportées ce jour ────────────────────────────────────────────
var owned_parcels: Array[ParcelData] = []

# ─── Statistiques globales ───────────────────────────────────────────────────
var total_earnings: int = 0
var days_survived: int = 0

# ─── Méthodes finances ────────────────────────────────────────────────────────

func can_afford(amount: int) -> bool:
	return money >= amount

func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	money -= amount
	return true

func earn(amount: int) -> void:
	money += amount
	total_earnings += amount

# ─── Méthodes inventaire ──────────────────────────────────────────────────────

func add_resource(resource: String, amount: int) -> void:
	if resource in inventory:
		inventory[resource] += amount

func get_total_inventory_value(prices: Dictionary) -> int:
	var total := 0
	for res in inventory:
		total += inventory[res] * prices.get(res, 0)
	return total

# ─── Méthodes recherche ───────────────────────────────────────────────────────

func has_research(research_id: String) -> bool:
	return research.get(research_id, 0) > 0

func get_research_level(research_id: String) -> int:
	return research.get(research_id, 0)

func unlock_research(research_id: String) -> void:
	research[research_id] = research.get(research_id, 0) + 1

# ─── Reset en début de journée ────────────────────────────────────────────────

func reset_day() -> void:
	owned_parcels.clear()
	for res in inventory:
		inventory[res] = 0
	days_survived += 1

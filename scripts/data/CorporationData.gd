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

# ─── Consommables (torches, dynamite…) — persistent, achetés au shop du soir ──
var consumables: Dictionary = { "torch": 0, "dynamite": 0 }

func add_consumable(id: String, n: int = 1) -> void:
	consumables[id] = int(consumables.get(id, 0)) + n

func consumable_count(id: String) -> int:
	return int(consumables.get(id, 0))

# Consomme une unité ; renvoie false s'il n'y en a plus.
func use_consumable(id: String) -> bool:
	if consumable_count(id) <= 0:
		return false
	consumables[id] = consumable_count(id) - 1
	return true

# ─── Parcelles remportées ce jour ────────────────────────────────────────────
var owned_parcels: Array[ParcelData] = []

# ─── Stockage loué (persiste d'un jour à l'autre, contre un loyer/nuit) ────────
# Catalogue des unités louables (id -> infos)
const STORAGE_UNITS: Dictionary = {
	"small":  { "name": "Petit", "capacity": 40,  "rent": 50  },
	"medium": { "name": "Moyen", "capacity": 100, "rent": 120 },
	"large":  { "name": "Grand", "capacity": 200, "rent": 250 },
}

# Liste des unités actuellement louées (ex: ["small", "small", "medium"])
var rented_storage: Array[String] = []

# Ressources entreposées (séparé du coffre / de l'inventaire du jour)
var storage: Dictionary = {
	"coal":    0,
	"iron":    0,
	"gold":    0,
	"gem":     0,
	"crystal": 0,
}

func storage_capacity() -> int:
	var c: int = 0
	for u in rented_storage:
		c += int(STORAGE_UNITS[u]["capacity"])
	return c

func storage_used() -> int:
	var s: int = 0
	for r in storage:
		s += int(storage[r])
	return s

func storage_room() -> int:
	return storage_capacity() - storage_used()

func storage_rent() -> int:
	var t: int = 0
	for u in rented_storage:
		t += int(STORAGE_UNITS[u]["rent"])
	return t

# Dépose jusqu'à `amount` unités, borné par la place restante. Retourne la quantité réellement déposée.
func add_to_storage(resource: String, amount: int) -> int:
	if resource not in storage:
		return 0
	var put: int = mini(amount, storage_room())
	if put > 0:
		storage[resource] += put
	return put

func rent_unit(unit_id: String) -> void:
	if unit_id in STORAGE_UNITS:
		rented_storage.append(unit_id)

# Résilie une unité — interdit si cela ferait passer le contenu au-dessus de la capacité.
func cancel_unit(unit_id: String) -> bool:
	if unit_id not in rented_storage:
		return false
	var new_cap: int = storage_capacity() - int(STORAGE_UNITS[unit_id]["capacity"])
	if storage_used() > new_cap:
		return false
	rented_storage.erase(unit_id)
	return true

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

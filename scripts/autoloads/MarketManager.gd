extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  MarketManager.gd  —  Autoload : "MarketManager"
#
#  Marché dynamique basé sur l'offre et la demande :
#  - Plus on vend d'une ressource → prix baisse
#  - Peu vendu → prix remonte
#  - Légère fluctuation aléatoire chaque jour
#  - Retour à la moyenne sur le long terme (mean reversion)
# ─────────────────────────────────────────────────────────────────────────────

# Prix de base par unité (en $)
const BASE_PRICES: Dictionary = {
	"coal":    5,
	"iron":    15,
	"gold":    80,
	"gem":     150,
	"crystal": 260,
}

# Limites des multiplicateurs
const MULT_MIN: float = 0.35
const MULT_MAX: float = 3.20

# ─── État du marché ───────────────────────────────────────────────────────────
var price_multipliers: Dictionary = {}
var price_history: Dictionary = {}      # { resource: Array[float] }  (10 derniers jours)

# ─── Signaux ──────────────────────────────────────────────────────────────────
signal prices_updated()

# ─────────────────────────────────────────────────────────────────────────────

func initialize() -> void:
	for resource in BASE_PRICES:
		price_multipliers[resource] = 1.0
		price_history[resource] = [1.0]

# ─── Lecture des prix ─────────────────────────────────────────────────────────

func get_price(resource: String) -> int:
	var base: int   = BASE_PRICES.get(resource, 0)
	var mult: float = price_multipliers.get(resource, 1.0)
	return int(float(base) * mult)

func get_all_prices() -> Dictionary:
	var prices: Dictionary = {}
	for resource in BASE_PRICES:
		prices[resource] = get_price(resource)
	return prices

# +1 si hausse, -1 si baisse, 0 si stable
func get_price_trend(resource: String) -> int:
	var history: Array = price_history.get(resource, [])
	if history.size() < 2:
		return 0
	var delta: float = float(history[-1]) - float(history[-2])
	if delta >  0.05: return  1
	if delta < -0.05: return -1
	return 0

func get_trend_icon(resource: String) -> String:
	var trend: int = get_price_trend(resource)
	if trend == 1:  return "▲"
	if trend == -1: return "▼"
	return "—"

# ─── Vente de ressources ──────────────────────────────────────────────────────

# Vend les ressources du joueur et retourne la somme gagnée.
func sell_resources(inventory: Dictionary) -> int:
	var total: int = 0
	for resource in inventory:
		var amount: int = inventory[resource]
		if amount <= 0:
			continue
		total += amount * get_price(resource)
	return total

# ─── Avancée journalière ──────────────────────────────────────────────────────

# Appelé en fin de phase Soir. sold_all = ressources vendues par TOUTES les corps ce jour.
func advance_day(sold_all: Dictionary) -> void:
	for resource in BASE_PRICES:
		var sold_amount: float = float(sold_all.get(resource, 0))
		var current:     float = float(price_multipliers[resource])

		# L'offre baisse le prix
		var supply_effect: float = -sold_amount * 0.0025

		# Fluctuation aléatoire quotidienne
		var noise: float = randf_range(-0.12, 0.12)

		# Mean reversion : le prix tend vers 1.0 sur le long terme
		var reversion: float = (1.0 - current) * 0.12

		var new_mult: float = clampf(current + supply_effect + noise + reversion, MULT_MIN, MULT_MAX)
		price_multipliers[resource] = new_mult

		# Historique (10 derniers jours)
		price_history[resource].append(new_mult)
		if price_history[resource].size() > 10:
			price_history[resource].pop_front()

	prices_updated.emit()

# ─── Collecte des ressources vendues par toutes les corps ────────────────────
# À appeler depuis EveningManager avant advance_day()
func aggregate_sold_resources(corps: Array[CorporationData]) -> Dictionary:
	var aggregate: Dictionary = {}
	for resource in BASE_PRICES:
		aggregate[resource] = 0
	for corp in corps:
		for resource in corp.inventory:
			if resource in aggregate:
				aggregate[resource] += corp.inventory[resource]
	return aggregate

extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  GameManager.gd  —  Autoload : "GameManager"
#  Singleton principal. Gère l'état du jeu, le cycle jour/nuit et les phases.
#
#  AUTOLOADS à déclarer dans Project > Project Settings > Autoload :
#    GameManager    → scripts/autoloads/GameManager.gd
#    ParcelGenerator→ scripts/autoloads/ParcelGenerator.gd
#    BiddingManager → scripts/autoloads/BiddingManager.gd
#    MarketManager  → scripts/autoloads/MarketManager.gd
#    ResearchManager→ scripts/autoloads/ResearchManager.gd
# ─────────────────────────────────────────────────────────────────────────────

enum GamePhase {
	MAIN_MENU,
	BIDDING,    # Sélection et enchères des parcelles
	MINING,     # Phase de mine en temps réel
	EVENING,    # Vente des ressources + R&D
}

# ─── Config ───────────────────────────────────────────────────────────────────
const STARTING_MONEY: int = 1000
const NUM_AI_CORPS: int = 3

var _ai_names:         Array[String] = ["IronFist Co.", "DeepEarth Ltd.", "StoneWall Inc."]
var _ai_colors:        Array[Color]  = [Color.RED, Color(0.2, 0.4, 1.0), Color.ORANGE]
var _ai_personalities: Array[int]    = [
	CorporationData.Personality.AGGRESSIVE,
	CorporationData.Personality.OPPORTUNIST,
	CorporationData.Personality.CONSERVATIVE,
]

# ─── État global ──────────────────────────────────────────────────────────────
var current_day: int = 0
var current_phase: GamePhase = GamePhase.MAIN_MENU
var player_corporation: CorporationData
var ai_corporations: Array[CorporationData] = []
var current_parcels: Array[ParcelData] = []

# ─── Signaux ──────────────────────────────────────────────────────────────────
signal phase_changed(new_phase: GamePhase)
signal day_started(day: int)
signal game_over(reason: String)

# ─────────────────────────────────────────────────────────────────────────────
#  INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────

func start_game(player_name: String = "Votre Corp") -> void:
	current_day = 0
	_create_corporations(player_name)
	ResearchManager.initialize()
	MarketManager.initialize()
	start_new_day()

func _create_corporations(player_name: String) -> void:
	player_corporation = CorporationData.new()
	player_corporation.corp_id   = 0
	player_corporation.corp_name = player_name
	player_corporation.money     = STARTING_MONEY
	player_corporation.is_player = true
	player_corporation.color     = Color.WHITE

	ai_corporations.clear()
	for i in NUM_AI_CORPS:
		var corp := CorporationData.new()
		corp.corp_id     = i + 1
		corp.corp_name   = _ai_names[i]
		corp.money       = STARTING_MONEY
		corp.is_player   = false
		corp.personality = _ai_personalities[i]
		corp.color       = _ai_colors[i]
		ai_corporations.append(corp)

# ─────────────────────────────────────────────────────────────────────────────
#  CYCLE DE JEU
# ─────────────────────────────────────────────────────────────────────────────

func start_new_day() -> void:
	current_day += 1

	# Reset inventaires (pas l'argent ni la recherche)
	for corp in get_all_corporations():
		corp.reset_day()

	# Générer les parcelles du jour
	current_parcels = ParcelGenerator.generate_parcels(current_day)

	# Lancer la phase d'enchères
	_change_phase(GamePhase.BIDDING)
	BiddingManager.start_auction(current_parcels)
	day_started.emit(current_day)

func start_mining_phase() -> void:
	# Appelé par BiddingManager après résolution des enchères
	_change_phase(GamePhase.MINING)

func start_evening_phase() -> void:
	# Appelé par la scène de mine quand la journée se termine
	_change_phase(GamePhase.EVENING)

func end_evening_phase(sold_resources: Dictionary) -> void:
	# Appelé par EveningUI après que le joueur a vendu et dépensé
	MarketManager.advance_day(sold_resources)

	# Vérification game over
	if player_corporation.money <= 50 and player_corporation.owned_parcels.is_empty():
		game_over.emit("Vous n'avez plus les fonds pour enchérir !")
		return

	start_new_day()

# Clôture du soir, pilotée par EveningUI quand le joueur lance la journée suivante.
# `player_sold` = quantités RÉELLEMENT vendues par le joueur ce soir (coffre + stockage).
func close_evening(player_sold: Dictionary) -> void:
	_change_phase(GamePhase.EVENING)

	# Loyer du stockage loué par le joueur (l'UI a déjà vérifié qu'il peut payer)
	player_corporation.spend(player_corporation.storage_rent())

	# Stub : les IA récoltent et vendent leur parcelle → gagnent + alimentent le marché
	var ai_sold: Dictionary = _simulate_ai_evening()

	# Offre totale du jour = ventes joueur + ventes IA
	var sold_all: Dictionary = {}
	for r in MarketManager.BASE_PRICES:
		sold_all[r] = int(player_sold.get(r, 0)) + int(ai_sold.get(r, 0))

	end_evening_phase(sold_all)

# Stub de revenu IA : chaque IA "mine" sa parcelle (estimé depuis profondeur + indice),
# vend tout au marché et encaisse. Retourne les quantités vendues par les IA.
func _simulate_ai_evening() -> Dictionary:
	var ai_sold: Dictionary = {}
	for r in MarketManager.BASE_PRICES:
		ai_sold[r] = 0

	for corp in ai_corporations:
		if corp.owned_parcels.is_empty():
			continue
		var haul: Dictionary = _estimate_ai_haul(corp.owned_parcels[0])
		var earned: int = 0
		for res in haul:
			var qty: int = haul[res]
			if qty <= 0:
				continue
			earned += qty * MarketManager.get_price(res)
			ai_sold[res] += qty
		corp.earn(earned)
	return ai_sold

func _estimate_ai_haul(parcel: ParcelData) -> Dictionary:
	var tier: int = parcel.depth_tier
	var haul: Dictionary = { "coal": 0, "iron": 0, "gold": 0, "gem": 0, "crystal": 0 }
	# Base de charbon, croissante avec la profondeur
	haul["coal"] = 18 + 10 * tier + randi() % 10
	# Ressource suggérée par l'indice de la parcelle
	var q: int = 8 + 6 * tier + randi() % 8
	match parcel.resource_hint:
		ParcelData.ResourceHint.IRON:    haul["iron"]    += q
		ParcelData.ResourceHint.GOLD:    haul["gold"]    += maxi(2, q / 3)
		ParcelData.ResourceHint.GEM:     haul["gem"]     += maxi(1, q / 4)
		ParcelData.ResourceHint.CRYSTAL: haul["crystal"] += maxi(1, q / 5)
		ParcelData.ResourceHint.COAL:    haul["coal"]    += q
	return haul

func _change_phase(new_phase: GamePhase) -> void:
	current_phase = new_phase
	phase_changed.emit(new_phase)

# ─────────────────────────────────────────────────────────────────────────────
#  UTILITAIRES
# ─────────────────────────────────────────────────────────────────────────────

func get_all_corporations() -> Array[CorporationData]:
	var all: Array[CorporationData] = [player_corporation]
	all.append_array(ai_corporations)
	return all

func get_corp_by_id(corp_id: int) -> CorporationData:
	if corp_id == 0:
		return player_corporation
	for corp in ai_corporations:
		if corp.corp_id == corp_id:
			return corp
	return null

func get_parcel_by_id(parcel_id: int) -> ParcelData:
	for parcel in current_parcels:
		if parcel.parcel_id == parcel_id:
			return parcel
	return null

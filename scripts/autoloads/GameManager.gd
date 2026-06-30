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
	GAME_OVER,  # Partie terminée (échec ou victoire)
}

# ─── Config ───────────────────────────────────────────────────────────────────
const STARTING_MONEY: int = 1000
const NUM_AI_CORPS: int = 3

# Licences : verrouillent la profondeur ET portent un PRÊT à rembourser.
# Remboursement 100% libre à chaque fin de semaine (tous les 30 jours) ; seule
# l'échéance finale compte : dette non soldée à l'échéance → game over.
# Solder la dette → licence suivante (profondeur + contrat plus gros).
# (Montants = principal bouton de difficulté, à ajuster après test.)
const LICENSES: Array = [
	{ "name": "Standard",     "max_tier": 1, "debt": 3500,  "deadline": 30 },
	{ "name": "Industrielle", "max_tier": 2, "debt": 7000,  "deadline": 60 },
	{ "name": "Volcanique",   "max_tier": 3, "debt": 11000, "deadline": 90 },
]
const WEEK_LENGTH: int = 7    # une "semaine" de jeu = 7 jours (remboursement hebdo)

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

# ─── Licences & prêt ──────────────────────────────────────────────────────────
var license_index: int = 0
var debt_paid: int = 0          # déjà remboursé sur le contrat courant
var end_message: String = ""    # message affiché en fin de partie

# ─── Signaux ──────────────────────────────────────────────────────────────────
signal phase_changed(new_phase: GamePhase)
signal day_started(day: int)
signal game_over(reason: String)
signal game_won(message: String)
signal license_upgraded(new_index: int)

# ─────────────────────────────────────────────────────────────────────────────
#  INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────

func start_game(player_name: String = "Votre Corp") -> void:
	current_day = 0
	license_index = 0
	debt_paid = 0
	end_message = ""
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

	# Générer les parcelles du jour (profondeur plafonnée par la licence)
	current_parcels = ParcelGenerator.generate_parcels(current_day)

	# Game over : impossible d'opérer si on ne peut s'offrir aucune parcelle
	if not _player_can_afford_any_parcel():
		_trigger_game_over("Faillite — vous ne pouvez plus vous offrir la moindre parcelle.")
		return

	# Lancer la phase d'enchères
	_change_phase(GamePhase.BIDDING)
	BiddingManager.start_auction(current_parcels)
	day_started.emit(current_day)

func _player_can_afford_any_parcel() -> bool:
	var cheapest: int = 1 << 30
	for p in current_parcels:
		cheapest = mini(cheapest, p.base_price)
	return player_corporation.money >= cheapest

func start_mining_phase() -> void:
	# Appelé par BiddingManager après résolution des enchères
	_change_phase(GamePhase.MINING)

func start_evening_phase() -> void:
	# Appelé par la scène de mine quand la journée se termine
	_change_phase(GamePhase.EVENING)

func end_evening_phase(sold_resources: Dictionary) -> void:
	# Appelé par EveningUI après que le joueur a vendu et dépensé.
	# Le remboursement de fin de semaine est résolu AVANT (resolve_weekend).
	MarketManager.advance_day(sold_resources)
	start_new_day()

# ─────────────────────────────────────────────────────────────────────────────
#  LICENCES & PRÊT
# ─────────────────────────────────────────────────────────────────────────────

func license_max_tier() -> int:
	return int(LICENSES[license_index]["max_tier"])

func license_name() -> String:
	return str(LICENSES[license_index]["name"])

func current_debt() -> int:
	return int(LICENSES[license_index]["debt"])

func debt_remaining() -> int:
	return maxi(0, current_debt() - debt_paid)

func current_deadline() -> int:
	return int(LICENSES[license_index]["deadline"])

func days_left() -> int:
	return maxi(0, current_deadline() - current_day)

# Jour de remboursement : chaque fin de semaine (7 j) OU le jour d'échéance.
func is_weekend() -> bool:
	if current_day <= 0:
		return false
	return current_day % WEEK_LENGTH == 0 or current_day == current_deadline()

# Rembourse un montant sur la dette courante (borné par l'argent et le restant).
func pay_debt(amount: int) -> void:
	var pay: int = clampi(amount, 0, mini(player_corporation.money, debt_remaining()))
	if pay <= 0:
		return
	player_corporation.spend(pay)
	debt_paid += pay

# Résolution de fin de semaine (appelée après le choix de remboursement).
# Renvoie true si la partie se termine (victoire ou game over).
func resolve_weekend() -> bool:
	# Dette soldée → licence suivante (ou victoire si c'était la dernière)
	if debt_paid >= current_debt():
		if license_index >= LICENSES.size() - 1:
			_trigger_win("VICTOIRE — tous les contrats honorés, licence Volcanique soldée !")
			return true
		license_index += 1
		debt_paid = 0
		license_upgraded.emit(license_index)
		return false

	# Échéance atteinte sans solder → game over
	if current_day >= current_deadline():
		_trigger_game_over("Échéance manquée — il restait %d$ à rembourser sur la licence %s." % [
			debt_remaining(), license_name()])
		return true

	return false

func _trigger_game_over(reason: String) -> void:
	end_message = reason
	_change_phase(GamePhase.GAME_OVER)
	game_over.emit(reason)

func _trigger_win(message: String) -> void:
	end_message = message
	_change_phase(GamePhase.GAME_OVER)
	game_won.emit(message)

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
	# Base de charbon, croissante avec la profondeur (bridée — stub temporaire,
	# une vraie simulation IA viendra plus tard).
	haul["coal"] = 9 + 5 * tier + randi() % 6
	# Ressource suggérée par l'indice de la parcelle
	var q: int = 4 + 3 * tier + randi() % 5
	match parcel.resource_hint:
		ParcelData.ResourceHint.IRON:    haul["iron"]    += q
		ParcelData.ResourceHint.GOLD:    haul["gold"]    += maxi(1, q / 3)
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

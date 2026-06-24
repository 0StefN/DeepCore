extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  BiddingManager.gd  —  Autoload : "BiddingManager"
#
#  Système d'enchères à plis fermés :
#  - Le joueur alloue son budget sur les parcelles qu'il veut en 60s
#  - Les IA calculent leurs mises en arrière-plan (invisible)
#  - À l'expiration (ou confirmation), toutes les mises sont révélées
#  - Le plus offrant remporte chaque parcelle (égalité = tirage aléatoire)
#  - Parcelles CONTESTED : les 2 plus offrants gagnent tous les deux
# ─────────────────────────────────────────────────────────────────────────────

const BIDDING_TIME: float = 60.0

# ─── État interne ─────────────────────────────────────────────────────────────
var player_bids: Dictionary = {}   # { parcel_id: int -> amount: int }
var ai_bids: Dictionary = {}       # { corp_id: int -> { parcel_id: int -> amount: int } }
var results: Dictionary = {}       # { parcel_id: int -> winner_id: int }   (-1 = personne)
var contested_results: Dictionary = {} # { parcel_id: int -> Array[int] }

var time_remaining: float = BIDDING_TIME
var bidding_active: bool = false

# ─── Signaux ──────────────────────────────────────────────────────────────────
signal bidding_started()
signal time_updated(time_left: float)
signal bid_updated(parcel_id: int, amount: int)    # Le joueur a modifié une mise
signal bidding_ended(results: Dictionary)          # Résultats finaux
signal bid_reveal_tick(parcel_id: int, corp_id: int, amount: int)  # Pour animation

# ─────────────────────────────────────────────────────────────────────────────
#  CYCLE GODOT
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not bidding_active:
		return
	time_remaining -= delta
	time_updated.emit(time_remaining)
	if time_remaining <= 0.0:
		end_bidding()

# ─────────────────────────────────────────────────────────────────────────────
#  DÉMARRAGE
# ─────────────────────────────────────────────────────────────────────────────

func start_bidding(parcels: Array[ParcelData]) -> void:
	player_bids.clear()
	ai_bids.clear()
	results.clear()
	contested_results.clear()
	time_remaining = BIDDING_TIME
	bidding_active = true

	# Initialiser les dicos IA
	for corp in GameManager.ai_corporations:
		ai_bids[corp.corp_id] = {}

	# Les IA calculent leurs mises immédiatement (scellées, révélées à la fin)
	_compute_all_ai_bids(parcels)

	bidding_started.emit()

# ─────────────────────────────────────────────────────────────────────────────
#  ACTIONS DU JOUEUR
# ─────────────────────────────────────────────────────────────────────────────

# Pose ou modifie la mise du joueur sur une parcelle.
# Retourne false si le budget est insuffisant.
func place_player_bid(parcel_id: int, amount: int) -> bool:
	# Calculer le total engagé hors cette parcelle
	var committed: int = 0
	for pid in player_bids:
		if pid != parcel_id:
			committed += player_bids[pid]

	if committed + amount > GameManager.player_corporation.money:
		return false

	if amount <= 0:
		player_bids.erase(parcel_id)
	else:
		player_bids[parcel_id] = amount

	bid_updated.emit(parcel_id, amount)
	return true

# Budget restant (argent du joueur moins ses mises en cours)
func get_player_remaining_budget() -> int:
	var committed: int = 0
	for amount in player_bids.values():
		committed += amount
	return GameManager.player_corporation.money - committed

# Mise courante du joueur sur une parcelle (0 si aucune)
func get_player_bid(parcel_id: int) -> int:
	return player_bids.get(parcel_id, 0)

# ─────────────────────────────────────────────────────────────────────────────
#  FIN DES ENCHÈRES
# ─────────────────────────────────────────────────────────────────────────────

func end_bidding() -> void:
	if not bidding_active:
		return
	bidding_active = false

	_resolve_all_bids()
	_apply_results()

	bidding_ended.emit(results)
	# Le GameManager transite vers MINING après un délai (géré dans BiddingUI)

# ─────────────────────────────────────────────────────────────────────────────
#  IA — CALCUL DES MISES
# ─────────────────────────────────────────────────────────────────────────────

func _compute_all_ai_bids(parcels: Array[ParcelData]) -> void:
	for corp in GameManager.ai_corporations:
		ai_bids[corp.corp_id] = _compute_corp_bids(corp, parcels)

func _compute_corp_bids(corp: CorporationData, parcels: Array[ParcelData]) -> Dictionary:
	var bids: Dictionary = {}
	var budget_left: int = corp.money

	# Trier les parcelles selon la personnalité
	var sorted := _sort_parcels_by_personality(corp.personality, parcels)

	for parcel in sorted:
		if budget_left <= 0:
			break
		# Parcelle réservée : vérifier la recherche
		if parcel.parcel_type == ParcelData.ParcelType.RESERVED:
			if not corp.has_research(parcel.required_research):
				continue

		var bid := _compute_single_bid(corp, parcel, budget_left)
		if bid > 0:
			bids[parcel.parcel_id] = bid
			budget_left -= bid

	return bids

func _sort_parcels_by_personality(
		personality: CorporationData.Personality,
		parcels: Array[ParcelData]) -> Array[ParcelData]:
	var sorted := parcels.duplicate()

	match personality:
		CorporationData.Personality.AGGRESSIVE:
			# Préfère les parcelles profondes et riches
			sorted.sort_custom(func(a: ParcelData, b: ParcelData) -> bool:
				return (a.depth_tier * 2 + _value_score(a)) > (b.depth_tier * 2 + _value_score(b))
			)
		CorporationData.Personality.OPPORTUNIST:
			# Adore les mystères et sous-évaluées
			sorted.sort_custom(func(a: ParcelData, b: ParcelData) -> bool:
				var sa := 4 if a.parcel_type == ParcelData.ParcelType.MYSTERY else _value_score(a)
				var sb := 4 if b.parcel_type == ParcelData.ParcelType.MYSTERY else _value_score(b)
				return sa > sb
			)
		CorporationData.Personality.CONSERVATIVE:
			# Ignore les risques, préfère les sûres
			sorted.sort_custom(func(a: ParcelData, b: ParcelData) -> bool:
				var safe_types := [ParcelData.ParcelType.MYSTERY, ParcelData.ParcelType.UNSTABLE]
				var sa := 0 if a.parcel_type in safe_types else _value_score(a)
				var sb := 0 if b.parcel_type in safe_types else _value_score(b)
				return sa > sb
			)
		CorporationData.Personality.TECHNO:
			# Cible les parcelles réservées en priorité
			sorted.sort_custom(func(a: ParcelData, b: ParcelData) -> bool:
				var sa := 6 if a.parcel_type == ParcelData.ParcelType.RESERVED else _value_score(a)
				var sb := 6 if b.parcel_type == ParcelData.ParcelType.RESERVED else _value_score(b)
				return sa > sb
			)

	return sorted

func _compute_single_bid(corp: CorporationData, parcel: ParcelData, budget_left: int) -> int:
	var base := float(parcel.base_price)
	var mult := 1.0

	match corp.personality:
		CorporationData.Personality.AGGRESSIVE:
			mult = randf_range(1.4, 2.1) if parcel.depth_tier == 3 else \
				   randf_range(1.1, 1.5) if parcel.depth_tier == 2 else \
				   randf_range(0.8, 1.1)

		CorporationData.Personality.OPPORTUNIST:
			if parcel.parcel_type == ParcelData.ParcelType.MYSTERY:
				mult = randf_range(1.2, 1.9)
			else:
				mult = randf_range(0.7, 1.05)

		CorporationData.Personality.CONSERVATIVE:
			if parcel.parcel_type in [ParcelData.ParcelType.MYSTERY, ParcelData.ParcelType.UNSTABLE]:
				return 0  # Refuse les parcelles risquées
			mult = randf_range(0.75, 1.0)

		CorporationData.Personality.TECHNO:
			if parcel.parcel_type == ParcelData.ParcelType.RESERVED:
				mult = randf_range(1.5, 2.0)
			else:
				mult = randf_range(0.6, 0.9)

	# Légère variation aléatoire pour rendre l'IA imprévisible
	mult += randf_range(-0.08, 0.08)

	var bid := int(base * mult)

	# Ne jamais dépasser 40% du budget total sur une seule parcelle
	var max_bid: int = mini(budget_left, int(float(corp.money) * 0.40))
	return clampi(bid, 0, max_bid)

func _value_score(parcel: ParcelData) -> int:
	match parcel.resource_hint:
		ParcelData.ResourceHint.CRYSTAL: return 5
		ParcelData.ResourceHint.GEM:     return 4
		ParcelData.ResourceHint.GOLD:    return 4
		ParcelData.ResourceHint.IRON:    return 2
		ParcelData.ResourceHint.COAL:    return 1
		ParcelData.ResourceHint.NONE:    return 0
	return 1

# ─────────────────────────────────────────────────────────────────────────────
#  RÉSOLUTION DES ENCHÈRES
# ─────────────────────────────────────────────────────────────────────────────

func _resolve_all_bids() -> void:
	for parcel: ParcelData in GameManager.current_parcels:
		if parcel.parcel_type == ParcelData.ParcelType.CONTESTED:
			contested_results[parcel.parcel_id] = _resolve_contested(parcel)
		else:
			results[parcel.parcel_id] = _resolve_standard(parcel)

func _resolve_standard(parcel: ParcelData) -> int:
	var all_bids: Dictionary = _collect_bids(parcel.parcel_id)

	if all_bids.is_empty():
		return -1  # Personne n'a enchéri

	var winner_id: int = -1
	var highest: int   = 0
	var tied: bool     = false

	for corp_id in all_bids:
		var amount: int = all_bids[corp_id]
		if amount > highest:
			highest   = amount
			winner_id = corp_id
			tied      = false
		elif amount == highest:
			tied = true

	# Tie-breaker : tirage aléatoire parmi les ex-aequo
	if tied:
		var candidates: Array = []
		for corp_id in all_bids:
			if all_bids[corp_id] == highest:
				candidates.append(corp_id)
		winner_id = candidates[randi() % candidates.size()]

	return winner_id

func _resolve_contested(parcel: ParcelData) -> Array:
	# Les 2 plus offrants gagnent l'accès
	var all_bids: Dictionary = _collect_bids(parcel.parcel_id)
	if all_bids.is_empty():
		return []

	# Trier par mise décroissante
	var sorted_ids: Array = all_bids.keys()
	sorted_ids.sort_custom(func(a, b) -> bool: return all_bids[a] > all_bids[b])

	return sorted_ids.slice(0, mini(2, sorted_ids.size()))

func _collect_bids(parcel_id: int) -> Dictionary:
	var all: Dictionary = {}

	if parcel_id in player_bids and player_bids[parcel_id] > 0:
		all[0] = player_bids[parcel_id]  # 0 = joueur

	for corp in GameManager.ai_corporations:
		var corp_bids: Dictionary = ai_bids.get(corp.corp_id, {})
		if parcel_id in corp_bids and corp_bids[parcel_id] > 0:
			all[corp.corp_id] = corp_bids[parcel_id]

	return all

# ─────────────────────────────────────────────────────────────────────────────
#  APPLICATION DES RÉSULTATS
# ─────────────────────────────────────────────────────────────────────────────

func _apply_results() -> void:
	for parcel: ParcelData in GameManager.current_parcels:
		var pid: int = parcel.parcel_id

		if parcel.parcel_type == ParcelData.ParcelType.CONTESTED:
			var winners: Array = contested_results.get(pid, [])
			for corp_id: int in winners:
				var corp: CorporationData = GameManager.get_corp_by_id(corp_id)
				if corp:
					var bid: int = _get_bid_amount(corp_id, pid)
					corp.spend(bid)
					corp.owned_parcels.append(parcel)
					parcel.owner_ids.append(corp_id)
			parcel.is_claimed = not parcel.owner_ids.is_empty()

		else:
			var winner_id: int = results.get(pid, -1)
			if winner_id >= 0:
				var corp: CorporationData = GameManager.get_corp_by_id(winner_id)
				if corp:
					var bid: int = _get_bid_amount(winner_id, pid)
					corp.spend(bid)
					corp.owned_parcels.append(parcel)
					parcel.owner_ids.append(winner_id)
					parcel.is_claimed = true

func _get_bid_amount(corp_id: int, parcel_id: int) -> int:
	if corp_id == 0:
		return player_bids.get(parcel_id, 0)
	return ai_bids.get(corp_id, {}).get(parcel_id, 0)

# ─────────────────────────────────────────────────────────────────────────────
#  HELPERS PUBLICS (pour l'UI)
# ─────────────────────────────────────────────────────────────────────────────

# Retourne true si le joueur a remporté cette parcelle
func player_won_parcel(parcel_id: int) -> bool:
	if GameManager.get_parcel_by_id(parcel_id).parcel_type == ParcelData.ParcelType.CONTESTED:
		return 0 in contested_results.get(parcel_id, [])
	return results.get(parcel_id, -1) == 0

# Retourne l'id du gagnant d'une parcelle (-1 si non réclamée)
func get_winner_id(parcel_id: int) -> int:
	return results.get(parcel_id, -1)

# Retourne les mises visibles de toutes les corps sur une parcelle (après révélation)
func get_all_bids_for_parcel(parcel_id: int) -> Dictionary:
	return _collect_bids(parcel_id)

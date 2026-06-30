extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  BiddingManager.gd  —  Autoload : "BiddingManager"
#
#  Enchère temps réel, vivante et réactive.
#  - Chaque compagnie repart avec UNE parcelle distincte (publique = filet).
#  - Les IA valorisent les parcelles au PRIX DU MARCHÉ (× richesse/profondeur),
#    plafonnées par leur argent et leur revenu moyen, modulées par personnalité.
#  - Évaluation CONTINUE : une IA peut délaisser sa parcelle pour une meilleure,
#    ou venir te déloger — y compris pour te bloquer (rivalité).
#  - Rythme étalé : hésitation par personnalité, les opportunistes observent
#    d'abord. On ne peut valider que lorsque le plateau s'est STABILISÉ.
# ─────────────────────────────────────────────────────────────────────────────

const AUCTION_TIME:  float = 60.0   # temps avant validation automatique
const TICK_INTERVAL: float = 0.7    # cadence des décisions IA (lisibilité)
const STABLE_DELAY:  float = 1.6    # plateau "stable" après ce temps sans action
const OBSERVE_TIME:  float = 6.0    # phase d'observation des opportunistes

# ─── Valuation ────────────────────────────────────────────────────────────────
const HAUL_Q:           float = 14.0   # quantité de référence par parcelle
const BID_BUDGET_FRAC:  float = 0.65   # part d'argent engageable sur une parcelle
const INCOME_FACTOR:    float = 1.0    # poids du revenu moyen dans le plafond
const SWITCH_MULT:      float = 1.3    # une IA ne change que pour un gain net nettement
const SWITCH_FLAT:      int   = 100    #   supérieur (anti-yoyo)
const DEPTH_MULT: Dictionary = { 1: 1.0, 2: 2.2, 3: 4.0 }

# ─── Hésitation (probabilité d'agir par tick selon la personnalité) ───────────
const ACT_AGGRESSIVE:    float = 0.85
const ACT_CONSERVATIVE:  float = 0.35
const ACT_TECHNO:        float = 0.50
const ACT_OPP_OBSERVE:   float = 0.15   # opportuniste pendant l'observation
const ACT_OPP_ACTIVE:    float = 0.60   # opportuniste après observation
const ACT_HOMELESS_MIN:  float = 0.70   # une compagnie sans parcelle s'active

# ─── Blocage / rivalité (bonus de préférence, ne dépasse jamais le plafond) ───
const DENIAL_AGGRESSIVE:  float = 0.50
const DENIAL_OPPORTUNIST: float = 0.15

# ─── État de l'enchère ────────────────────────────────────────────────────────
var active: bool = false
var time_remaining: float = AUCTION_TIME

var pool: Array[ParcelData] = []
var public_parcel: ParcelData = null

var holder: Dictionary = {}             # parcel_id -> corp_id (-1 = libre)
var bid:    Dictionary = {}             # parcel_id -> prix courant
var target: Dictionary = {}             # corp_id   -> parcel_id (-1 = sans parcelle)
var settled_public: Dictionary = {}     # corp_id   -> bool

var ai_desire: Dictionary = {}          # corp_id -> { pid -> désir (préférence) }
var ai_maxpay: Dictionary = {}          # corp_id -> { pid -> plafond de mise }

var player_target_max: int = 0

var _tick_accum: float = 0.0
var _time_since_action: float = 999.0
var _was_settled: bool = false

# ─── Signaux ──────────────────────────────────────────────────────────────────
signal auction_started()
signal board_changed()
signal time_updated(time_left: float)
signal settled_changed(is_settled: bool)
signal player_outbid(parcel_id: int)
signal auction_validated()

# ─────────────────────────────────────────────────────────────────────────────
#  CYCLE GODOT
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not active:
		return

	time_remaining -= delta
	time_updated.emit(time_remaining)
	if time_remaining <= 0.0:
		validate()
		return

	_time_since_action += delta
	_tick_accum += delta
	while _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_tick()

	var s: bool = is_settled()
	if s != _was_settled:
		_was_settled = s
		settled_changed.emit(s)

# ─────────────────────────────────────────────────────────────────────────────
#  DÉMARRAGE
# ─────────────────────────────────────────────────────────────────────────────

func start_auction(parcels: Array[ParcelData]) -> void:
	pool.clear()
	public_parcel = null
	holder.clear()
	bid.clear()
	target.clear()
	settled_public.clear()
	ai_desire.clear()
	ai_maxpay.clear()
	player_target_max = 0
	_tick_accum = 0.0
	_time_since_action = 999.0
	_was_settled = false
	time_remaining = AUCTION_TIME

	for p in parcels:
		if p.is_public:
			public_parcel = p
		else:
			pool.append(p)
			holder[p.parcel_id] = -1
			bid[p.parcel_id]    = p.base_price

	for corp in GameManager.get_all_corporations():
		target[corp.corp_id] = -1
		settled_public[corp.corp_id] = false

	_precompute_valuations()

	active = true
	auction_started.emit()
	board_changed.emit()
	settled_changed.emit(false)

# ─────────────────────────────────────────────────────────────────────────────
#  VALUATION (prix marché × richesse, plafonnée par argent + revenu)
# ─────────────────────────────────────────────────────────────────────────────

func _precompute_valuations() -> void:
	for corp: CorporationData in GameManager.ai_corporations:
		var desire: Dictionary = {}
		var maxpay: Dictionary = {}
		var afford: int = _afford_cap(corp)
		for p: ParcelData in pool:
			var d: int = 0
			var m: int = 0
			# Parcelle réservée hors de portée → aucune valeur
			if not (p.parcel_type == ParcelData.ParcelType.RESERVED \
					and not corp.has_research(p.required_research)):
				var haul: float = _est_haul(p)
				var app:  float = _appetite(corp, p)
				d = int(haul * app)
				m = mini(d, afford)
			desire[p.parcel_id] = d
			maxpay[p.parcel_id] = m
		ai_desire[corp.corp_id] = desire
		ai_maxpay[corp.corp_id] = maxpay

# Plafond engageable : part de l'argent + revenu moyen par jour, borné par l'argent.
func _afford_cap(corp: CorporationData) -> int:
	var avg_income: int = 0
	if corp.days_survived > 0:
		avg_income = int(float(corp.total_earnings) / float(corp.days_survived))
	var cap: int = int(float(corp.money) * BID_BUDGET_FRAC + float(avg_income) * INCOME_FACTOR)
	return mini(corp.money, cap)

# Valeur de récolte estimée depuis les infos VISIBLES (pas de triche).
func _est_haul(p: ParcelData) -> float:
	var price: float = float(_hint_price(p))
	var dm:    float = float(DEPTH_MULT.get(p.depth_tier, 1.0))
	return HAUL_Q * dm * price

func _hint_price(p: ParcelData) -> int:
	match p.resource_hint:
		ParcelData.ResourceHint.COAL:    return MarketManager.get_price("coal")
		ParcelData.ResourceHint.IRON:    return MarketManager.get_price("iron")
		ParcelData.ResourceHint.GOLD:    return MarketManager.get_price("gold")
		ParcelData.ResourceHint.GEM:     return MarketManager.get_price("sapphire")
		ParcelData.ResourceHint.CRYSTAL: return MarketManager.get_price("diamond")
		ParcelData.ResourceHint.NONE:    return int(float(MarketManager.get_price("coal")) * 0.6)
	# UNKNOWN (Mystère) : espérance moyenne du marché — un pari
	var all: Dictionary = MarketManager.get_all_prices()
	var sum: int = 0
	for r in all:
		sum += all[r]
	return int(float(sum) / float(maxi(1, all.size())))

# Appétit selon la personnalité (coefficient appliqué à la récolte estimée).
func _appetite(corp: CorporationData, p: ParcelData) -> float:
	match corp.personality:
		CorporationData.Personality.AGGRESSIVE:
			var a: float = 0.90
			if p.depth_tier == 3: a += 0.25
			if p.parcel_type == ParcelData.ParcelType.UNSTABLE: a += 0.15
			if p.parcel_type == ParcelData.ParcelType.MYSTERY:  a = 0.70
			return a
		CorporationData.Personality.OPPORTUNIST:
			if p.parcel_type == ParcelData.ParcelType.MYSTERY:  return 1.10
			if p.parcel_type == ParcelData.ParcelType.UNSTABLE: return 0.85
			return 0.80
		CorporationData.Personality.CONSERVATIVE:
			if p.parcel_type in [ParcelData.ParcelType.MYSTERY, ParcelData.ParcelType.UNSTABLE]:
				return 0.0
			return 0.70
		CorporationData.Personality.TECHNO:
			if p.parcel_type == ParcelData.ParcelType.RESERVED:
				return 1.20
			return 0.70
	return 0.70

# ─────────────────────────────────────────────────────────────────────────────
#  TICK IA — évaluation continue + hésitation
# ─────────────────────────────────────────────────────────────────────────────

func _tick() -> void:
	if not active:
		return

	var ais: Array = GameManager.ai_corporations.duplicate()
	ais.shuffle()
	var leader: int = _money_leader_id()
	var acted: bool = false

	for corp: CorporationData in ais:
		if not _ai_should_act(corp):
			continue

		var move: Dictionary = _ai_best_move(corp, leader)
		if not move.is_empty():
			_apply_claim(corp.corp_id, int(move["pid"]), int(move["cost"]))
			acted = true
			break

		# Pas de meilleur coup : si sans parcelle, se rabattre / se replier
		if target.get(corp.corp_id, -1) == -1 and not settled_public.get(corp.corp_id, false):
			var fb: Dictionary = _ai_fallback_free(corp)
			if not fb.is_empty():
				_apply_claim(corp.corp_id, int(fb["pid"]), int(fb["cost"]))
			else:
				settled_public[corp.corp_id] = true
				_time_since_action = 0.0
			acted = true
			break
		# Sinon (tient déjà une parcelle, rien de mieux) : on laisse, au suivant

	if acted:
		board_changed.emit()

func _ai_should_act(corp: CorporationData) -> bool:
	# Déjà repliée sur la publique → ne fait plus rien
	if settled_public.get(corp.corp_id, false):
		return false

	var elapsed: float = AUCTION_TIME - time_remaining
	var chance: float = ACT_CONSERVATIVE
	match corp.personality:
		CorporationData.Personality.AGGRESSIVE:
			chance = ACT_AGGRESSIVE
		CorporationData.Personality.CONSERVATIVE:
			chance = ACT_CONSERVATIVE
		CorporationData.Personality.TECHNO:
			chance = ACT_TECHNO
		CorporationData.Personality.OPPORTUNIST:
			chance = ACT_OPP_OBSERVE if elapsed < OBSERVE_TIME else ACT_OPP_ACTIVE

	# Sans parcelle → plus pressée
	if target.get(corp.corp_id, -1) == -1:
		chance = maxf(chance, ACT_HOMELESS_MIN)

	return randf() < chance

# Meilleur coup pour cette IA (peut déloger un autre, y compris le joueur).
func _ai_best_move(corp: CorporationData, leader: int) -> Dictionary:
	var desire: Dictionary = ai_desire.get(corp.corp_id, {})
	var maxpay: Dictionary = ai_maxpay.get(corp.corp_id, {})

	var cur: int = target.get(corp.corp_id, -1)
	var cur_net: int = (int(desire.get(cur, 0)) - bid.get(cur, 0)) if cur != -1 else 0

	# Pour changer de parcelle, il faut un gain net > actuel + marge (anti-yoyo).
	# Sans parcelle, on prend tout coup net positif.
	var best: Dictionary = {}
	var best_net: int = 0 if cur == -1 else int(float(cur_net) * SWITCH_MULT) + SWITCH_FLAT

	for p: ParcelData in pool:
		var pid: int = p.parcel_id
		var d: int   = int(desire.get(pid, 0))
		if d <= 0:
			continue
		var h: int = holder.get(pid, -1)
		if h == corp.corp_id:
			continue
		var cost: int = bid[pid] if h == -1 else bid[pid] + _inc(bid[pid])
		if cost > int(maxpay.get(pid, 0)) or cost > corp.money:
			continue

		var net: int = d - cost
		# Bonus de blocage : préférence pour déloger le joueur / le leader
		if h != -1 and h != corp.corp_id and _is_denial_target(h, leader):
			net += int(float(d) * _denial_weight(corp))

		if net > best_net:
			best_net = net
			best = { "pid": pid, "cost": cost }

	return best

func _ai_fallback_free(corp: CorporationData) -> Dictionary:
	var best: Dictionary = {}
	var cheapest: int = 1 << 30
	for p: ParcelData in pool:
		var pid: int = p.parcel_id
		if holder.get(pid, -1) != -1:
			continue
		var cost: int = bid[pid]
		if cost <= corp.money and cost < cheapest:
			cheapest = cost
			best = { "pid": pid, "cost": cost }
	return best

func _is_denial_target(corp_id: int, leader: int) -> bool:
	return corp_id == 0 or corp_id == leader

func _denial_weight(corp: CorporationData) -> float:
	match corp.personality:
		CorporationData.Personality.AGGRESSIVE:  return DENIAL_AGGRESSIVE
		CorporationData.Personality.OPPORTUNIST: return DENIAL_OPPORTUNIST
	return 0.0

func _money_leader_id() -> int:
	var best_id: int = -1
	var best_money: int = -1
	for corp: CorporationData in GameManager.get_all_corporations():
		if corp.money > best_money:
			best_money = corp.money
			best_id = corp.corp_id
	return best_id

# ─────────────────────────────────────────────────────────────────────────────
#  APPLICATION D'UNE MISE
# ─────────────────────────────────────────────────────────────────────────────

func _apply_claim(corp_id: int, pid: int, cost: int) -> void:
	var prev: int = holder.get(pid, -1)

	var old: int = target.get(corp_id, -1)
	if old != -1 and old != pid and holder.get(old, -1) == corp_id:
		holder[old] = -1
		bid[old]    = _base_of(old)

	holder[pid] = corp_id
	bid[pid]    = cost
	target[corp_id] = pid
	settled_public[corp_id] = false
	_time_since_action = 0.0

	if prev != -1 and prev != corp_id:
		target[prev] = -1
		if prev == 0:
			_player_auto_react(pid)
			if holder.get(pid, -1) != 0:
				player_outbid.emit(pid)

func _player_auto_react(pid: int) -> void:
	var cur: int = bid[pid]
	var rc: int  = cur + _inc(cur)
	if rc <= player_target_max and rc <= GameManager.player_corporation.money:
		_apply_claim(0, pid, rc)

# ─────────────────────────────────────────────────────────────────────────────
#  ACTIONS DU JOUEUR
# ─────────────────────────────────────────────────────────────────────────────

func set_player_target(pid: int, max_bid: int) -> bool:
	if not active or pid not in bid:
		return false

	var p: ParcelData = GameManager.get_parcel_by_id(pid)
	if p and p.parcel_type == ParcelData.ParcelType.RESERVED:
		if not GameManager.player_corporation.has_research(p.required_research):
			return false

	if holder.get(pid, -1) == 0:
		player_target_max = maxi(max_bid, bid[pid])
		board_changed.emit()
		return true

	var cost: int = get_cost_to_take(pid)
	if cost > GameManager.player_corporation.money or cost > max_bid:
		return false

	player_target_max = max_bid
	_apply_claim(0, pid, cost)
	board_changed.emit()
	return true

func clear_player_target() -> void:
	var pid: int = target.get(0, -1)
	if pid != -1 and holder.get(pid, -1) == 0:
		holder[pid] = -1
		bid[pid]    = _base_of(pid)
		target[0]   = -1
	player_target_max = 0
	_time_since_action = 0.0
	board_changed.emit()

func get_cost_to_take(pid: int) -> int:
	var h: int = holder.get(pid, -1)
	if h == 0 or h == -1:
		return bid.get(pid, 0)
	return bid[pid] + _inc(bid[pid])

# ─────────────────────────────────────────────────────────────────────────────
#  VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

func validate() -> void:
	if not active:
		return
	active = false

	for corp: CorporationData in GameManager.get_all_corporations():
		var pid: int = target.get(corp.corp_id, -1)
		var parcel: ParcelData
		var price: int
		if pid == -1:
			parcel = public_parcel
			price  = public_parcel.base_price if public_parcel else 0
		else:
			parcel = GameManager.get_parcel_by_id(pid)
			price  = bid[pid]
		if parcel == null:
			continue
		corp.spend(price)
		corp.owned_parcels.append(parcel)
		parcel.owner_ids.append(corp.corp_id)
		parcel.is_claimed = true

	auction_validated.emit()

# ─────────────────────────────────────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _inc(current: int) -> int:
	return maxi(15, int(round(float(current) * 0.12 / 5.0)) * 5)

func _base_of(pid: int) -> int:
	var p: ParcelData = GameManager.get_parcel_by_id(pid)
	return p.base_price if p else 0

# ─── Requêtes pour l'UI ───────────────────────────────────────────────────────

func get_holder(pid: int) -> int:
	return holder.get(pid, -1)

func get_bid(pid: int) -> int:
	return bid.get(pid, 0)

func get_player_target() -> int:
	return target.get(0, -1)

func get_player_committed() -> int:
	var pid: int = target.get(0, -1)
	return bid.get(pid, 0) if pid != -1 else 0

func get_company_parcel_id(corp_id: int) -> int:
	var pid: int = target.get(corp_id, -1)
	if pid != -1:
		return pid
	if settled_public.get(corp_id, false) and public_parcel:
		return public_parcel.parcel_id
	return -1

# Plafond de mise d'une IA sur une parcelle donnée (pour le Réseau d'Espions).
func get_ai_maxpay(corp_id: int, pid: int) -> int:
	var caps: Dictionary = ai_maxpay.get(corp_id, {})
	return int(caps.get(pid, 0))

func get_homeless_ai_count() -> int:
	var n: int = 0
	for corp: CorporationData in GameManager.ai_corporations:
		if target.get(corp.corp_id, -1) == -1 and not settled_public.get(corp.corp_id, false):
			n += 1
	return n

# Plateau stable : tout le monde placé, le joueur tient une parcelle, et plus
# aucune action depuis STABLE_DELAY (les IA peuvent te souffler une parcelle
# tant que ce n'est pas stable).
func is_settled() -> bool:
	return get_homeless_ai_count() == 0 \
		and target.get(0, -1) != -1 \
		and _time_since_action >= STABLE_DELAY

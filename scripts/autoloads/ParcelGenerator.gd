extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  ParcelGenerator.gd  —  Autoload : "ParcelGenerator"
#  Génère la grille de parcelles de chaque journée.
#  Profondeur = num_paliers (1 à 8). Pas de plafond de licence (les licences
#  deviendront des BIOMES). Les minerais présents et le minerai le plus rare sont
#  pré-tirés (seedés) pour que l'intel de la Phase 2 corresponde à la vraie mine.
# ─────────────────────────────────────────────────────────────────────────────

const GRID_COLUMNS: int = 4
const EXTRA_PARCELS: int = 4

# Prix de base par type de sol
const SOIL_BASE_PRICE: Dictionary = {
	ParcelData.SoilType.CLAY:      50,
	ParcelData.SoilType.LIMESTONE: 110,
	ParcelData.SoilType.GRANITE:   190,
	ParcelData.SoilType.VOLCANIC:  280,
}

# Bonus de présence des minerais selon la richesse de la parcelle.
const RICHNESS_PRESENCE_BONUS: Dictionary = {
	ParcelData.Richness.POOR:   0.00,
	ParcelData.Richness.MEDIUM: 0.05,
	ParcelData.Richness.RICH:   0.12,
	ParcelData.Richness.LOADED: 0.20,
}

# Multiplicateur de quantité approximative (actual_resources) selon la richesse.
const RICHNESS_RESOURCE_MULT: Dictionary = {
	ParcelData.Richness.POOR:   0.40,
	ParcelData.Richness.MEDIUM: 1.00,
	ParcelData.Richness.RICH:   1.90,
	ParcelData.Richness.LOADED: 3.50,
}

# ─────────────────────────────────────────────────────────────────────────────
#  ENTRÉE PRINCIPALE
# ─────────────────────────────────────────────────────────────────────────────

func generate_parcels(day: int) -> Array[ParcelData]:
	var parcels: Array[ParcelData] = []
	var id_counter: int = 0

	parcels.append(_make_public_parcel(id_counter))
	id_counter += 1

	var num_corps: int = GameManager.get_all_corporations().size()
	var count: int = num_corps + EXTRA_PARCELS
	for i in count:
		var pos := Vector2i(i % GRID_COLUMNS, i / GRID_COLUMNS)
		parcels.append(_make_parcel(id_counter, pos, day))
		id_counter += 1

	return parcels

# ─────────────────────────────────────────────────────────────────────────────
#  CONSTRUCTION D'UNE PARCELLE
# ─────────────────────────────────────────────────────────────────────────────

func _make_parcel(id: int, pos: Vector2i, day: int) -> ParcelData:
	var p := ParcelData.new()
	p.parcel_id        = id
	p.grid_position    = pos
	p.generation_seed  = randi() | 1
	p.num_paliers      = _pick_paliers(pos, day)
	p.depth_tier       = _paliers_to_tier(p.num_paliers)
	p.soil_type        = _pick_soil(p.num_paliers)
	p.parcel_type      = _pick_type(day)
	p.richness         = _pick_richness()

	# Pré-tirage des minerais présents (seedé → cohérent avec la mine).
	p.present_ores     = _roll_present_ores(p)
	p.rarest_ore       = OreDB.rarest_of(p.present_ores)
	p.resource_hint    = _hint_from_rarest(p)
	p.actual_resources = _approx_resources(p)

	# Prix de base : sol + profondeur (par palier).
	var base_price: int = SOIL_BASE_PRICE.get(p.soil_type, 110)
	var depth_mult: float = 1.0 + float(p.num_paliers - 1) * 0.30
	p.base_price = int(float(base_price) * depth_mult)

	match p.parcel_type:
		ParcelData.ParcelType.MYSTERY:
			p.base_price = int(p.base_price * 0.55)
			p.resource_hint = ParcelData.ResourceHint.UNKNOWN
		ParcelData.ParcelType.UNSTABLE:
			p.base_price = int(p.base_price * 0.80)
		ParcelData.ParcelType.CONTESTED:
			p.base_price = int(p.base_price * 1.10)
		ParcelData.ParcelType.RESERVED:
			p.base_price = int(p.base_price * 1.25)
			p.required_research = _pick_required_research(p.depth_tier)

	if p.parcel_type == ParcelData.ParcelType.UNSTABLE:
		p.collapse_chance = randf_range(0.10, 0.45)

	return p

func _make_public_parcel(id: int) -> ParcelData:
	var p := ParcelData.new()
	p.parcel_id        = id
	p.grid_position    = Vector2i(-1, -1)
	p.generation_seed  = randi() | 1
	p.num_paliers      = 2
	p.depth_tier       = 1
	p.soil_type        = ParcelData.SoilType.CLAY
	p.parcel_type      = ParcelData.ParcelType.NORMAL
	p.base_price       = 50
	p.is_public        = true
	p.richness         = _pick_richness()
	p.present_ores     = _roll_present_ores(p)
	p.rarest_ore       = OreDB.rarest_of(p.present_ores)
	p.resource_hint    = _hint_from_rarest(p)
	p.actual_resources = _approx_resources(p)
	return p

# ─────────────────────────────────────────────────────────────────────────────
#  PICKERS
# ─────────────────────────────────────────────────────────────────────────────

# Profondeur en paliers (1 à 8). La droite de la grille et les jours avancés
# tendent vers le profond.
func _pick_paliers(pos: Vector2i, day: int) -> int:
	var x_bias: float   = float(pos.x) / float(GRID_COLUMNS)
	var day_bias: float = minf(float(day) * 0.02, 0.45)
	var deep: float     = clampf(0.10 + x_bias * 0.22 + day_bias, 0.05, 0.80)

	var roll := randf()
	if roll < deep * 0.35:
		return randi_range(7, 8)
	elif roll < deep:
		return randi_range(5, 6)
	elif roll < deep + 0.40:
		return randi_range(3, 4)
	return randi_range(1, 2)

func _paliers_to_tier(paliers: int) -> int:
	if paliers <= 3: return 1
	if paliers <= 6: return 2
	return 3

func _pick_soil(paliers: int) -> ParcelData.SoilType:
	var roll := randf()
	if paliers <= 2:
		if roll < 0.55: return ParcelData.SoilType.CLAY
		elif roll < 0.88: return ParcelData.SoilType.LIMESTONE
		return ParcelData.SoilType.GRANITE
	elif paliers <= 5:
		if roll < 0.15: return ParcelData.SoilType.CLAY
		elif roll < 0.55: return ParcelData.SoilType.LIMESTONE
		elif roll < 0.85: return ParcelData.SoilType.GRANITE
		return ParcelData.SoilType.VOLCANIC
	if roll < 0.35: return ParcelData.SoilType.GRANITE
	return ParcelData.SoilType.VOLCANIC

func _pick_type(day: int) -> ParcelData.ParcelType:
	var special_chance: float = minf(0.22 + float(day) * 0.008, 0.42)
	if randf() > special_chance:
		return ParcelData.ParcelType.NORMAL
	var roll := randf()
	if roll < 0.40:   return ParcelData.ParcelType.MYSTERY
	elif roll < 0.72: return ParcelData.ParcelType.UNSTABLE
	return ParcelData.ParcelType.RESERVED

func _pick_required_research(tier: int) -> String:
	match tier:
		1: return "drill_basic"
		2: return "drill_advanced"
		3: return "drill_volcanic"
	return "drill_basic"

func _pick_richness() -> ParcelData.Richness:
	var roll := randf()
	if roll < 0.04:   return ParcelData.Richness.LOADED   #  4 %
	elif roll < 0.22: return ParcelData.Richness.RICH     # 18 %
	elif roll < 0.72: return ParcelData.Richness.MEDIUM   # 50 %
	return ParcelData.Richness.POOR                       # 28 %

# ─────────────────────────────────────────────────────────────────────────────
#  PRÉ-TIRAGE DES MINERAIS (seedé)
# ─────────────────────────────────────────────────────────────────────────────

# Quels minerais sont réellement présents ? Plus la parcelle descend sous le
# palier de spawn d'un minerai, plus il a de chances d'être là. Fuite jackpot
# très rare d'un minerai un palier plus profond que la parcelle.
func _roll_present_ores(p: ParcelData) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.generation_seed
	var bonus: float = RICHNESS_PRESENCE_BONUS.get(p.richness, 0.0)
	var present: Array[String] = []

	for id in OreDB.get_ids():
		var sp: int = OreDB.get_palier(id)
		if sp <= p.num_paliers:
			var depth_into: int = p.num_paliers - sp
			var chance: float = clampf(0.32 + float(depth_into) * 0.17 + bonus, 0.0, 0.96)
			if rng.randf() < chance:
				present.append(id)
		elif sp == p.num_paliers + 1:
			# Fuite très rare d'un minerai du palier suivant (jackpot)
			if rng.randf() < 0.05 + bonus * 0.4:
				present.append(id)

	if present.is_empty():
		present.append("coal")
	return present

# Catégorie grossière (compat BiddingManager / GameManager / ParcelCard).
func _hint_from_rarest(p: ParcelData) -> ParcelData.ResourceHint:
	if p.rarest_ore == "":
		return ParcelData.ResourceHint.NONE
	var sp: int = OreDB.get_palier(p.rarest_ore)
	if sp <= 1:   return ParcelData.ResourceHint.COAL
	elif sp == 2: return ParcelData.ResourceHint.IRON
	elif sp <= 4: return ParcelData.ResourceHint.GOLD
	elif sp <= 5: return ParcelData.ResourceHint.GEM
	return ParcelData.ResourceHint.CRYSTAL

# Quantités approximatives (legacy actual_resources, panneau d'enchère).
func _approx_resources(p: ParcelData) -> Dictionary:
	var mult: float = RICHNESS_RESOURCE_MULT.get(p.richness, 1.0)
	var res: Dictionary = {}
	for id in p.present_ores:
		var sp: int = OreDB.get_palier(id)
		var depth_into: int = maxi(0, p.num_paliers - sp)
		var qty: int = int(float(randi_range(6, 18) + depth_into * 4) * mult)
		res[id] = maxi(1, qty)
	return res

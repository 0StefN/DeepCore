extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  ParcelGenerator.gd  —  Autoload : "ParcelGenerator"
#  Génère la grille de parcelles pour chaque journée.
#  La difficulté et la richesse évoluent avec le numéro de jour.
# ─────────────────────────────────────────────────────────────────────────────

const GRID_COLUMNS: int = 4
# Nombre de parcelles compétitives = nb de compagnies + marge de choix.
const EXTRA_PARCELS: int = 4

# Prix de base par type de sol
const SOIL_BASE_PRICE: Dictionary = {
	ParcelData.SoilType.CLAY:      50,
	ParcelData.SoilType.LIMESTONE: 110,
	ParcelData.SoilType.GRANITE:   190,
	ParcelData.SoilType.VOLCANIC:  280,
}

# Multiplicateur prix selon la profondeur
const DEPTH_PRICE_MULT: Dictionary = {
	1: 1.0,
	2: 1.6,
	3: 2.5,
}

# Multiplicateur de ressources selon la richesse (doit suivre RICHNESS_DENSITY_MULT
# côté MineGenerator pour que le Sondage reste honnête).
const RICHNESS_RESOURCE_MULT: Dictionary = {
	ParcelData.Richness.POOR:    0.40,
	ParcelData.Richness.NORMAL:  1.00,
	ParcelData.Richness.RICH:    1.90,
	ParcelData.Richness.BONANZA: 3.50,
}

# ─────────────────────────────────────────────────────────────────────────────
#  ENTRÉE PRINCIPALE
# ─────────────────────────────────────────────────────────────────────────────

func generate_parcels(day: int) -> Array[ParcelData]:
	var parcels: Array[ParcelData] = []
	var id_counter: int = 0

	# 1 parcelle publique gratuite (filet de sécurité, toujours disponible)
	parcels.append(_make_public_parcel(id_counter))
	id_counter += 1

	# Parcelles compétitives : une par compagnie + quelques extras
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
	p.parcel_id      = id
	p.grid_position  = pos
	p.depth_tier     = _pick_depth(pos, day)
	p.soil_type      = _pick_soil(p.depth_tier)
	p.parcel_type    = _pick_type(day)
	p.resource_hint  = _pick_hint(p.depth_tier, p.parcel_type)
	p.richness       = _pick_richness()

	# Prix de base
	var base_price: int   = SOIL_BASE_PRICE[p.soil_type]
	var depth_mult: float = DEPTH_PRICE_MULT[p.depth_tier]
	p.base_price = int(base_price * depth_mult)

	# Ajustements de prix selon le type spécial
	match p.parcel_type:
		ParcelData.ParcelType.MYSTERY:
			p.base_price = int(p.base_price * 0.55)  # Moins chère car risquée
		ParcelData.ParcelType.UNSTABLE:
			p.base_price = int(p.base_price * 0.80)  # Légère réduction
		ParcelData.ParcelType.CONTESTED:
			p.base_price = int(p.base_price * 1.10)  # Légèrement plus chère
		ParcelData.ParcelType.RESERVED:
			p.base_price = int(p.base_price * 1.25)  # Premium
			p.required_research = _pick_required_research(p.depth_tier)

	# Ressources réelles (cachées au joueur)
	p.actual_resources = _generate_resources(p)

	# Chance d'effondrement pour UNSTABLE
	if p.parcel_type == ParcelData.ParcelType.UNSTABLE:
		p.collapse_chance = randf_range(0.10, 0.45)

	return p

func _make_public_parcel(id: int) -> ParcelData:
	# Parcelle "starter" : toujours disponible et bon marché, mais PLUS gratuite
	# (filet de sécurité payant). Sa richesse varie comme les autres.
	var p := ParcelData.new()
	p.parcel_id        = id
	p.grid_position    = Vector2i(-1, -1)
	p.depth_tier       = 1
	p.soil_type        = ParcelData.SoilType.CLAY
	p.parcel_type      = ParcelData.ParcelType.NORMAL
	p.resource_hint    = ParcelData.ResourceHint.COAL
	p.base_price       = 50
	p.is_public        = true
	p.richness         = _pick_richness()
	p.actual_resources = _generate_resources(p)
	return p

# ─────────────────────────────────────────────────────────────────────────────
#  PICKERS
# ─────────────────────────────────────────────────────────────────────────────

func _pick_depth(pos: Vector2i, day: int) -> int:
	# La droite de la grille (x élevé) tend à être plus profonde
	var x_bias: float = float(pos.x) / float(GRID_COLUMNS)

	# Les jours avancés offrent plus de parcelles profondes
	var day_bias: float = minf(float(day) * 0.015, 0.3)

	var deep_chance := clampf(0.08 + x_bias * 0.20 + day_bias, 0.05, 0.55)
	var mid_chance  := clampf(0.25 + x_bias * 0.10 + day_bias * 0.5, 0.20, 0.50)

	var tier: int = 1
	var roll := randf()
	if roll < deep_chance:
		tier = 3
	elif roll < deep_chance + mid_chance:
		tier = 2

	# La licence plafonne la profondeur accessible (L1 = tier 1 seulement)
	return mini(tier, GameManager.license_max_tier())

func _pick_soil(depth: int) -> ParcelData.SoilType:
	var roll := randf()
	match depth:
		1:
			if roll < 0.50: return ParcelData.SoilType.CLAY
			elif roll < 0.85: return ParcelData.SoilType.LIMESTONE
			else: return ParcelData.SoilType.GRANITE
		2:
			if roll < 0.10: return ParcelData.SoilType.CLAY
			elif roll < 0.50: return ParcelData.SoilType.LIMESTONE
			elif roll < 0.85: return ParcelData.SoilType.GRANITE
			else: return ParcelData.SoilType.VOLCANIC
		3:
			if roll < 0.30: return ParcelData.SoilType.GRANITE
			else: return ParcelData.SoilType.VOLCANIC
	return ParcelData.SoilType.LIMESTONE

func _pick_type(day: int) -> ParcelData.ParcelType:
	# Taux de parcelles spéciales augmente légèrement avec les jours
	var special_chance: float = minf(0.22 + float(day) * 0.008, 0.42)

	if randf() > special_chance:
		return ParcelData.ParcelType.NORMAL

	var roll := randf()
	if roll < 0.40:   return ParcelData.ParcelType.MYSTERY
	elif roll < 0.72: return ParcelData.ParcelType.UNSTABLE
	else:             return ParcelData.ParcelType.RESERVED

func _pick_hint(depth: int, ptype: ParcelData.ParcelType) -> ParcelData.ResourceHint:
	if ptype == ParcelData.ParcelType.MYSTERY:
		return ParcelData.ResourceHint.UNKNOWN  # Masqué

	var roll := randf()
	match depth:
		1:
			if roll < 0.55: return ParcelData.ResourceHint.COAL
			elif roll < 0.80: return ParcelData.ResourceHint.IRON
			elif roll < 0.93: return ParcelData.ResourceHint.NONE
			else: return ParcelData.ResourceHint.GOLD
		2:
			if roll < 0.25: return ParcelData.ResourceHint.COAL
			elif roll < 0.50: return ParcelData.ResourceHint.IRON
			elif roll < 0.72: return ParcelData.ResourceHint.GOLD
			elif roll < 0.90: return ParcelData.ResourceHint.GEM
			else: return ParcelData.ResourceHint.CRYSTAL
		3:
			if roll < 0.10: return ParcelData.ResourceHint.IRON
			elif roll < 0.32: return ParcelData.ResourceHint.GOLD
			elif roll < 0.62: return ParcelData.ResourceHint.GEM
			else: return ParcelData.ResourceHint.CRYSTAL
	return ParcelData.ResourceHint.COAL

func _pick_required_research(depth: int) -> String:
	match depth:
		1: return "drill_basic"
		2: return "drill_advanced"
		3: return "drill_volcanic"
	return "drill_basic"

# Richesse de la parcelle (cachée, révélée par le Sondage). Filon très rare.
func _pick_richness() -> ParcelData.Richness:
	var roll := randf()
	if roll < 0.04:   return ParcelData.Richness.BONANZA  #  4 %
	elif roll < 0.22: return ParcelData.Richness.RICH     # 18 %
	elif roll < 0.72: return ParcelData.Richness.NORMAL   # 50 %
	return ParcelData.Richness.POOR                       # 28 %

# ─────────────────────────────────────────────────────────────────────────────
#  GÉNÉRATION DES RESSOURCES CACHÉES
# ─────────────────────────────────────────────────────────────────────────────

func _generate_resources(p: ParcelData) -> Dictionary:
	var base: int
	match p.depth_tier:
		1: base = randi_range(15,  45)
		2: base = randi_range(40,  90)
		3: base = randi_range(80, 180)
		_: base = 20

	# Modificateurs selon le type de parcelle
	match p.parcel_type:
		ParcelData.ParcelType.MYSTERY:
			var roll := randf()
			if   roll < 0.20: return {}                         # Vide !
			elif roll < 0.50: base = randi_range(5,  20)       # Pauvre
			elif roll < 0.80: base = randi_range(50, 110)      # Bon
			else:             base = randi_range(120, 250)     # Jackpot !
		ParcelData.ParcelType.UNSTABLE:
			base = int(base * randf_range(1.6, 2.8))           # Très riche mais risqué
		ParcelData.ParcelType.RESERVED:
			base = int(base * randf_range(1.3, 1.8))           # Bonus de ressources

	# Richesse de la parcelle (Pauvre → Filon) : échelle commune avec la densité de mine
	base = int(base * RICHNESS_RESOURCE_MULT.get(p.richness, 1.0))

	# Résoudre le hint pour les mystères
	var hint := p.resource_hint
	if hint == ParcelData.ResourceHint.UNKNOWN:
		hint = _pick_hint(p.depth_tier, ParcelData.ParcelType.NORMAL)

	# Assigner les ressources selon le hint principal
	var res: Dictionary = {}
	match hint:
		ParcelData.ResourceHint.COAL:
			res["coal"] = base
			if randf() < 0.35: res["iron"] = randi_range(5, 18)
		ParcelData.ResourceHint.IRON:
			res["iron"] = base
			res["coal"] = randi_range(8, 25)
		ParcelData.ResourceHint.GOLD:
			res["gold"] = int(base * 0.28)
			res["iron"] = randi_range(10, 30)
		ParcelData.ResourceHint.GEM:
			res["gem"]  = int(base * 0.18)
			res["iron"] = randi_range(5, 20)
			if randf() < 0.4: res["gold"] = randi_range(3, 10)
		ParcelData.ResourceHint.CRYSTAL:
			res["crystal"] = int(base * 0.12)
			res["gem"]     = randi_range(5, 15)
			if randf() < 0.5: res["gold"] = randi_range(5, 18)
		ParcelData.ResourceHint.NONE:
			res["coal"] = randi_range(2, 8)  # Toujours un tout petit peu

	return res

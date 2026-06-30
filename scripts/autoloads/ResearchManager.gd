extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  ResearchManager.gd  —  Autoload : "ResearchManager"
#
#  Arbre de recherche technologique.
#  Les nœuds sont définis ici comme données statiques.
#  Les effets sont lus par les autres systèmes via get_effect().
# ─────────────────────────────────────────────────────────────────────────────

# Arbre complet des recherches
var _tree: Dictionary = {}  # { id: ResearchNode }

signal research_unlocked(research_id: String, level: int)

# ─────────────────────────────────────────────────────────────────────────────
#  INITIALISATION — Définition de l'arbre
# ─────────────────────────────────────────────────────────────────────────────

func initialize() -> void:
	_tree.clear()
	_register_all_nodes()

func _register_all_nodes() -> void:

	# ── MINING (ligne 0) ──────────────────────────────────────────────────────
	_add("pickaxe_upgrade", "Pioche Améliorée", "Mine plus vite (+50% au niveau 1, puis +30% par niveau, jusqu'au niveau 10).",
		ResearchNode.Category.MINING, 100, [],
		"mining_speed", 0.50, 0.30, 10, Vector2i(0, 0))
	_add("drill_basic", "Foreuse Basique", "Débloque les parcelles Réservées (profondeur 1).",
		ResearchNode.Category.MINING, 300, ["pickaxe_upgrade"],
		"unlock_reserved_1", 1.0, 0.0, 1, Vector2i(1, 0))
	_add("drill_advanced", "Foreuse Avancée", "Débloque les parcelles Réservées (profondeur 2). +15% vitesse de minage.",
		ResearchNode.Category.MINING, 550, ["drill_basic"],
		"mining_speed", 0.15, 0.0, 1, Vector2i(2, 0))
	_add("drill_volcanic", "Foreuse Volcanique", "Débloque les parcelles Réservées (profondeur 3).",
		ResearchNode.Category.MINING, 900, ["drill_advanced"],
		"unlock_reserved_3", 1.0, 0.0, 1, Vector2i(3, 0))

	# ── EXPLOSIFS (ligne 1) — à venir ─────────────────────────────────────────
	_add("explosives_basic", "Dynamite", "Débloque l'achat de dynamite (détruit les blocs en zone, +50% de rayon par niveau).",
		ResearchNode.Category.EXPLOSIVES, 400, ["pickaxe_upgrade"],
		"explosives_radius", 1.0, 0.5, 3, Vector2i(1, 1))
	_add("explosives_chain", "Charges en Chaîne", "Les explosions peuvent en déclencher d'autres.",
		ResearchNode.Category.EXPLOSIVES, 700, ["explosives_basic"],
		"explosives_chain", 1.0, 0.0, 1, Vector2i(2, 1), true)

	# ── ÉQUIPEMENT / MOBILITÉ (lignes 2-4) ────────────────────────────────────
	_add("backpack_upgrade", "Sac Renforcé", "Augmente la taille des piles du sac (+4 par niveau).",
		ResearchNode.Category.LOGISTICS, 200, [],
		"stack_bonus", 4.0, 4.0, 3, Vector2i(0, 2))
	_add("inventory_slots", "Cases Supplémentaires", "Ajoute une case d'inventaire (+1 par niveau).",
		ResearchNode.Category.LOGISTICS, 250, ["backpack_upgrade"],
		"slot_bonus", 1.0, 1.0, 3, Vector2i(1, 2))
	_add("magnet", "Aimant Amélioré", "Augmente le rayon de ramassage des ressources (+0.6 tuile/niveau).",
		ResearchNode.Category.LOGISTICS, 220, [],
		"pickup_radius", 0.6, 0.6, 3, Vector2i(2, 2))
	_add("lamp", "Lampe de Casque", "Éclaire les alentours du joueur dans la mine.",
		ResearchNode.Category.LOGISTICS, 300, [],
		"light_radius", 2.0, 1.0, 3, Vector2i(3, 2))

	_add("boots", "Bottes Renforcées", "Augmente la vitesse de déplacement (+25% au niveau 1, +20% par niveau suivant).",
		ResearchNode.Category.LOGISTICS, 200, [],
		"move_speed", 0.25, 0.20, 3, Vector2i(0, 3))
	_add("jump_upgrade", "Saut Amélioré", "Saut plus vif : atteint sa hauteur plus vite (+25% au niveau 1, +20% au niveau 2).",
		ResearchNode.Category.LOGISTICS, 240, ["boots"],
		"jump_power", 0.25, 0.20, 2, Vector2i(1, 3))
	_add("jetpack", "Jetpack", "Permet de voler dans la mine en maintenant Saut.",
		ResearchNode.Category.LOGISTICS, 900, ["jump_upgrade"],
		"jetpack_enabled", 1.0, 0.0, 1, Vector2i(2, 3))
	_add("jetpack_fuel", "Jetpack : Réservoir", "Augmente l'autonomie de vol (+50% par niveau).",
		ResearchNode.Category.LOGISTICS, 500, ["jetpack"],
		"jetpack_fuel", 0.50, 0.50, 3, Vector2i(3, 3))
	_add("jetpack_thrust", "Jetpack : Propulsion", "Augmente la poussée et la vitesse de montée (+20% par niveau).",
		ResearchNode.Category.LOGISTICS, 500, ["jetpack"],
		"jetpack_thrust", 0.20, 0.20, 3, Vector2i(2, 4))
	_add("jetpack_recharge", "Jetpack : Recharge", "Recharge le carburant plus vite au sol (+30% par niveau).",
		ResearchNode.Category.LOGISTICS, 500, ["jetpack"],
		"jetpack_recharge", 0.30, 0.30, 3, Vector2i(3, 4))

	# ── LOGISTIQUE / STOCKAGE (lignes 5-6) ────────────────────────────────────
	_add("elevator", "Ascenseur", "Remonte instantanément à la surface depuis la mine.",
		ResearchNode.Category.LOGISTICS, 600, ["jump_upgrade"],
		"elevator_enabled", 1.0, 0.0, 1, Vector2i(0, 5), true)
	_add("minecart", "Wagonnet", "Transport automatique des ressources (mineurs IA).",
		ResearchNode.Category.LOGISTICS, 450, ["backpack_upgrade"],
		"minecart_enabled", 1.0, 0.0, 1, Vector2i(1, 5), true)
	_add("storage_2", "Entrepôt II", "Débloque la location du stockage Moyen.",
		ResearchNode.Category.LOGISTICS, 300, [],
		"storage_unlock", 1.0, 0.0, 1, Vector2i(0, 6))
	_add("storage_3", "Entrepôt III", "Débloque la location du stockage Grand.",
		ResearchNode.Category.LOGISTICS, 600, ["storage_2"],
		"storage_unlock", 1.0, 0.0, 1, Vector2i(1, 6))

	# ── TRAITEMENT (ligne 7) ──────────────────────────────────────────────────
	_add("smelter", "Fonderie", "Convertit le fer brut en lingots (+30% valeur).",
		ResearchNode.Category.PROCESSING, 350, [],
		"iron_value_bonus", 0.30, 0.15, 3, Vector2i(0, 7))
	_add("refinery", "Raffinerie", "Raffine l'or et les gemmes (+40% valeur).",
		ResearchNode.Category.PROCESSING, 600, ["smelter"],
		"precious_value_bonus", 0.40, 0.20, 2, Vector2i(1, 7))

	# ── RENSEIGNEMENT (ligne 8) ───────────────────────────────────────────────
	# (Le « Sondage Géologique » a été remplacé par les bouquets d'intel du Soir.)
	_add("spy_network", "Réseau d'Espions", "Révèle les mises des corporations rivales pendant l'enchère.",
		ResearchNode.Category.INTELLIGENCE, 700, [],
		"spy_reveal_bids", 1.0, 0.0, 1, Vector2i(0, 8))

# Helper pour enregistrer un nœud
func _add(
		id: String, name: String, desc: String,
		cat: ResearchNode.Category, cost: int,
		prereqs: Array[String],
		effect_key: String, effect_val: float, effect_per_lvl: float,
		max_lvl: int, pos: Vector2i, coming: bool = false
	) -> void:
	var node := ResearchNode.new()
	node.id              = id
	node.display_name    = name
	node.description     = desc
	node.category        = cat
	node.cost            = cost
	node.prerequisites   = prereqs
	node.effect_key      = effect_key
	node.effect_value    = effect_val
	node.effect_per_level = effect_per_lvl
	node.max_level       = max_lvl
	node.tree_pos        = pos
	node.coming_soon     = coming
	_tree[id] = node

# ─────────────────────────────────────────────────────────────────────────────
#  LECTURE
# ─────────────────────────────────────────────────────────────────────────────

func get_research_node(research_id: String) -> ResearchNode:
	return _tree.get(research_id, null)

func get_all_nodes() -> Array:
	return _tree.values()

func get_nodes_by_category(cat: ResearchNode.Category) -> Array:
	var result: Array = []
	for node in _tree.values():
		if node.category == cat:
			result.append(node)
	return result

# ─────────────────────────────────────────────────────────────────────────────
#  VÉRIFICATION & DÉBLOCAGE (pour le joueur)
# ─────────────────────────────────────────────────────────────────────────────

func can_research(research_id: String, corp: CorporationData) -> bool:
	var node := get_research_node(research_id)
	if not node:
		return false

	# Pas encore disponible ("à venir")
	if node.coming_soon:
		return false

	# Niveau max atteint ?
	var current_level := corp.get_research_level(research_id)
	if current_level >= node.max_level:
		return false

	# Prérequis satisfaits ?
	for prereq in node.prerequisites:
		if not corp.has_research(prereq):
			return false

	# Budget suffisant ?
	var cost := node.get_total_cost(current_level)
	return corp.can_afford(cost)

func research(research_id: String, corp: CorporationData) -> bool:
	if not can_research(research_id, corp):
		return false

	var node: ResearchNode = get_research_node(research_id)
	var level: int = corp.get_research_level(research_id)
	var cost: int  = node.get_total_cost(level)

	corp.spend(cost)
	corp.unlock_research(research_id)
	research_unlocked.emit(research_id, level + 1)
	return true

# ─────────────────────────────────────────────────────────────────────────────
#  LECTURE DES EFFETS (pour les autres systèmes)
# ─────────────────────────────────────────────────────────────────────────────

# Retourne la valeur de l'effet pour une corporation donnée
func get_effect(effect_key: String, corp: CorporationData) -> float:
	var total := 0.0
	for node in _tree.values():
		if node.effect_key != effect_key:
			continue
		var level := corp.get_research_level(node.id)
		if level > 0:
			total += node.get_effect_at_level(level)
	return total

# Raccourcis pratiques
func get_mining_speed_bonus(corp: CorporationData) -> float:
	return get_effect("mining_speed", corp)

func get_carry_capacity_bonus(corp: CorporationData) -> int:
	return int(get_effect("carry_capacity", corp))

# Rayon d'aimantation des drops (en tuiles). 0 tant qu'aucun nœud "pickup_radius"
# n'existe — prêt à être branché sur une future recherche.
func get_pickup_radius_bonus(corp: CorporationData) -> float:
	return get_effect("pickup_radius", corp)

func get_iron_value_bonus(corp: CorporationData) -> float:
	return get_effect("iron_value_bonus", corp)

func get_precious_value_bonus(corp: CorporationData) -> float:
	return get_effect("precious_value_bonus", corp)

func has_elevator(corp: CorporationData) -> bool:
	return corp.has_research("elevator")

func has_minecart(corp: CorporationData) -> bool:
	return corp.has_research("minecart")

func can_access_reserved(corp: CorporationData, depth_tier: int) -> bool:
	match depth_tier:
		1: return corp.has_research("drill_basic")
		2: return corp.has_research("drill_advanced")
		3: return corp.has_research("drill_volcanic")
	return false

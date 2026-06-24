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

	# ── MINING ────────────────────────────────────────────────────────────────
	_add("pickaxe_upgrade",
		"Pic Renforcé", "Mine 20% plus vite.",
		ResearchNode.Category.MINING, 150, [],
		"mining_speed", 0.20, 0.10, 3
	)
	_add("drill_basic",
		"Foreuse Basique", "Débloque les parcelles Réservées (profondeur 1).",
		ResearchNode.Category.MINING, 300, ["pickaxe_upgrade"],
		"unlock_reserved_1", 1.0, 0.0, 1
	)
	_add("drill_advanced",
		"Foreuse Avancée", "Débloque les parcelles Réservées (profondeur 2). +15% vitesse.",
		ResearchNode.Category.MINING, 550, ["drill_basic"],
		"unlock_reserved_2", 1.0, 0.0, 1
	)
	_add("drill_volcanic",
		"Foreuse Volcanique", "Débloque les parcelles Réservées (profondeur 3). Résiste à la chaleur.",
		ResearchNode.Category.MINING, 900, ["drill_advanced"],
		"unlock_reserved_3", 1.0, 0.0, 1
	)
	_add("explosives_basic",
		"Dynamite", "Permet de poser des charges pour détruire les blocs en zone.",
		ResearchNode.Category.EXPLOSIVES, 400, ["pickaxe_upgrade"],
		"explosives_radius", 1.0, 0.5, 3
	)
	_add("explosives_chain",
		"Charges en Chaîne", "Les explosions peuvent en déclencher d'autres.",
		ResearchNode.Category.EXPLOSIVES, 700, ["explosives_basic"],
		"explosives_chain", 1.0, 0.0, 1
	)

	# ── LOGISTICS ─────────────────────────────────────────────────────────────
	_add("backpack_upgrade",
		"Sac Renforcé", "+20 unités de capacité de portage par niveau.",
		ResearchNode.Category.LOGISTICS, 200, [],
		"carry_capacity", 20.0, 20.0, 4
	)
	_add("minecart",
		"Wagonnet", "Les mineurs IA déposent leurs ressources dans des wagonnets automatiques.",
		ResearchNode.Category.LOGISTICS, 450, ["backpack_upgrade"],
		"minecart_enabled", 1.0, 0.0, 1
	)
	_add("elevator",
		"Ascenseur", "Remonte à la surface instantanément depuis n'importe quelle profondeur.",
		ResearchNode.Category.LOGISTICS, 600, ["minecart"],
		"elevator_enabled", 1.0, 0.0, 1
	)

	# ── PROCESSING ────────────────────────────────────────────────────────────
	_add("smelter",
		"Fonderie", "Convertit le fer brut en lingots (+30% valeur).",
		ResearchNode.Category.PROCESSING, 350, [],
		"iron_value_bonus", 0.30, 0.15, 3
	)
	_add("refinery",
		"Raffinerie", "Raffine l'or et les gemmes (+40% valeur).",
		ResearchNode.Category.PROCESSING, 600, ["smelter"],
		"precious_value_bonus", 0.40, 0.20, 2
	)

	# ── INTELLIGENCE ──────────────────────────────────────────────────────────
	_add("survey_basic",
		"Sondage Géologique", "Révèle la quantité approximative des ressources d'une parcelle avant achat.",
		ResearchNode.Category.INTELLIGENCE, 300, [],
		"survey_accuracy", 0.5, 0.25, 2
	)
	_add("spy_network",
		"Réseau d'Espions", "Révèle les mises des corporations rivales avant la fin du temps d'enchères.",
		ResearchNode.Category.INTELLIGENCE, 700, ["survey_basic"],
		"spy_reveal_bids", 1.0, 0.0, 1
	)

# Helper pour enregistrer un nœud
func _add(
		id: String, name: String, desc: String,
		cat: ResearchNode.Category, cost: int,
		prereqs: Array[String],
		effect_key: String, effect_val: float, effect_per_lvl: float,
		max_lvl: int = 1
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

class_name ResearchNode
extends Resource

# ─────────────────────────────────────────────────────────────────────────────
#  ResearchNode.gd
#  Définit un nœud de l'arbre de recherche.
#  Chaque nœud a des prérequis, un coût et un effet appliqué via ResearchManager.
# ─────────────────────────────────────────────────────────────────────────────

enum Category {
	MINING,       # Vitesse, puissance de minage
	LOGISTICS,    # Portage, remontée, ascenseurs
	PROCESSING,   # Raffinage des ressources
	INTELLIGENCE, # Info sur les parcelles, espionnage des rivaux
	EXPLOSIVES,   # Dynamite, foreuses, explosifs avancés
}

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var category: Category = Category.MINING
@export var cost: int = 200
@export var prerequisites: Array[String] = []  # IDs des nœuds requis
@export var unlocks_parcel_type: String = ""   # Si non vide, débloque les parcelles RESERVED de ce type
@export var max_level: int = 1                 # Permet la recherche à plusieurs niveaux

# Disposition dans l'arbre (grille) et état "à venir"
@export var tree_pos: Vector2i = Vector2i.ZERO  # Colonne, ligne dans l'arbre
@export var coming_soon: bool = false           # Visible mais pas encore achetable

# Effets — interprétés par ResearchManager
@export var effect_key: String = ""    # Ex: "mining_speed", "carry_capacity"
@export var effect_value: float = 0.0  # Ex: 0.2 = +20%
@export var effect_per_level: float = 0.0  # Bonus supplémentaire par niveau


func get_effect_at_level(level: int) -> float:
	return effect_value + effect_per_level * (level - 1)

func get_total_cost(current_level: int) -> int:
	# Chaque niveau suivant coûte 50% de plus
	return int(cost * pow(1.5, current_level))

class_name ParcelData
extends Resource

# ─────────────────────────────────────────────────────────────────────────────
#  ParcelData.gd
#  Données d'une parcelle de terrain. Utilisé comme Resource (pas de node).
#  Les champs "actual_*" sont cachés au joueur jusqu'à ce qu'il mine.
# ─────────────────────────────────────────────────────────────────────────────

enum SoilType {
	CLAY,       # Argile  : rapide à miner, peu de valeur
	LIMESTONE,  # Calcaire: standard
	GRANITE,    # Granit  : lent, ressources rares
	VOLCANIC,   # Volcanique: très lent, très rare
}

enum ParcelType {
	NORMAL,
	MYSTERY,    # Infos cachées, prix réduit — jackpot ou vide
	UNSTABLE,   # Ressources abondantes mais risque d'effondrement
	CONTESTED,  # Les 2 plus offrants peuvent miner simultanément
	RESERVED,   # Nécessite une recherche spécifique pour enchérir
}

enum ResourceHint {
	NONE,      # Peu prometteur
	COAL,      # Charbon
	IRON,      # Fer
	GOLD,      # Or
	GEM,       # Gemmes
	CRYSTAL,   # Cristaux
	UNKNOWN,   # Parcelle Mystère — hint masqué
}

enum Richness {
	POOR,      # Pauvre  : peu de minerai
	NORMAL,    # Normale : standard (rentable)
	RICH,      # Riche   : bien fournie
	BONANZA,   # Filon   : jackpot, très rare
}

# ─── Infos visibles avant achat ───────────────────────────────────────────────
@export var parcel_id: int = 0
@export var grid_position: Vector2i = Vector2i.ZERO
@export var soil_type: SoilType = SoilType.LIMESTONE
@export var parcel_type: ParcelType = ParcelType.NORMAL
@export var depth_tier: int = 1          # 1 = peu profond, 2 = moyen, 3 = très profond
@export var resource_hint: ResourceHint = ResourceHint.COAL
@export var base_price: int = 100
@export var required_research: String = ""  # Pour les parcelles RESERVED

# ─── Infos cachées, révélées pendant la mine ──────────────────────────────────
var actual_resources: Dictionary = {}    # { "coal": 50, "iron": 20, … }
var richness: Richness = Richness.NORMAL  # Densité réelle de la mine (révélée par Sondage)
var collapse_chance: float = 0.0        # Pour UNSTABLE
var is_public: bool = false             # Parcelle publique gratuite

# ─── État enchère/mine ────────────────────────────────────────────────────────
var is_claimed: bool = false
var owner_ids: Array[int] = []          # Peut contenir 2 ids pour CONTESTED

# ─── Helpers d'affichage ──────────────────────────────────────────────────────

func get_display_name() -> String:
	match parcel_type:
		ParcelType.MYSTERY:   return "Parcelle Mystère"
		ParcelType.UNSTABLE:  return "Parcelle Instable"
		ParcelType.CONTESTED: return "Parcelle Contestée"
		ParcelType.RESERVED:  return "Parcelle Réservée"
	return "Parcelle %d" % parcel_id

func get_type_icon() -> String:
	match parcel_type:
		ParcelType.MYSTERY:   return "❓"
		ParcelType.UNSTABLE:  return "⚠"
		ParcelType.CONTESTED: return "⚔"
		ParcelType.RESERVED:  return "🔒"
	return ""

func get_soil_display() -> String:
	match soil_type:
		SoilType.CLAY:      return "Argile"
		SoilType.LIMESTONE: return "Calcaire"
		SoilType.GRANITE:   return "Granit"
		SoilType.VOLCANIC:  return "Volcanique"
	return "Inconnu"

func get_resource_display() -> String:
	if parcel_type == ParcelType.MYSTERY:
		return "???"
	match resource_hint:
		ResourceHint.COAL:    return "Charbon"
		ResourceHint.IRON:    return "Fer"
		ResourceHint.GOLD:    return "Or"
		ResourceHint.GEM:     return "Gemmes"
		ResourceHint.CRYSTAL: return "Cristaux"
		ResourceHint.NONE:    return "Pauvre"
	return "Inconnu"

func get_depth_display() -> String:
	match depth_tier:
		1: return "Peu profonde"
		2: return "Profonde"
		3: return "Très profonde"
	return "?"

func get_depth_icon() -> String:
	match depth_tier:
		1: return "🟢"
		2: return "🟡"
		3: return "🔴"
	return "⚪"

func get_richness_display() -> String:
	match richness:
		Richness.POOR:    return "Pauvre"
		Richness.NORMAL:  return "Normale"
		Richness.RICH:    return "Riche"
		Richness.BONANZA: return "Filon !"
	return "?"

func is_owned_by(corp_id: int) -> bool:
	return corp_id in owner_ids

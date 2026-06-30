extends Node

# ─────────────────────────────────────────────────────────────────────────────
#  OreData.gd  —  Autoload : "OreDB"
#
#  SOURCE UNIQUE DE VÉRITÉ pour tous les minerais et les couches de profondeur.
#  Ajouter un minerai = UNE entrée dans ORES (+ une case de couleur dans le PNG
#  placeholder, même ordre). Tout le reste (marché, génération, drops, UI) lit ici.
#
#  Système de paliers (= couches géologiques, surface → noyau, 1 à 8) :
#   - Un minerai de palier de spawn S n'apparaît que dans les couches L >= S,
#     plus une fuite très rare dans la couche L == S-1.
#   - Rendement par tuile dans la couche L = L - S + 1 (1 à son palier de spawn).
#   - Abondance : culmine au palier de spawn puis décroît en profondeur
#     (les communs s'effacent quand on descend → chaque couche est dominée par
#     les minerais de son propre tier). Valeurs validées par tools/economy_sim.py.
# ─────────────────────────────────────────────────────────────────────────────

const N_PALIERS:   int   = 8
const DEEP_DECAY:  float = 0.52   # facteur d'abondance par couche sous le spawn
const LEAK_FACTOR: float = 0.04   # abondance de la fuite rare une couche au-dessus

# id → { display, palier, price, mine_time, peak, color, atlas_x }
#   palier    = palier de spawn (couche la moins profonde où il apparaît)
#   price     = prix de base ($/unité)
#   mine_time = temps de minage de la tuile minerai (s)
#   peak      = abondance relative à son palier de spawn
#   color     = teinte placeholder (doit suivre l'ordre du PNG ore_overlay)
#   atlas_x   = colonne dans ore_overlay.png (= ordre d'insertion ici)
const ORES: Dictionary = {
	"coal":       { "display": "Charbon",    "palier": 1, "price": 6,     "mine_time": 1.4, "peak": 100, "color": Color(0.13, 0.13, 0.15), "atlas_x": 0 },
	"copper":     { "display": "Cuivre",     "palier": 1, "price": 12,    "mine_time": 1.5, "peak": 78,  "color": Color(0.80, 0.45, 0.22), "atlas_x": 1 },
	"iron":       { "display": "Fer",        "palier": 1, "price": 16,    "mine_time": 1.6, "peak": 72,  "color": Color(0.62, 0.64, 0.68), "atlas_x": 2 },
	"quartz":     { "display": "Quartz",     "palier": 1, "price": 24,    "mine_time": 1.7, "peak": 55,  "color": Color(0.90, 0.90, 0.86), "atlas_x": 3 },
	"tin":        { "display": "Étain",      "palier": 2, "price": 34,    "mine_time": 2.0, "peak": 60,  "color": Color(0.66, 0.70, 0.74), "atlas_x": 4 },
	"lapis":      { "display": "Lapis",      "palier": 2, "price": 52,    "mine_time": 2.0, "peak": 46,  "color": Color(0.16, 0.28, 0.74), "atlas_x": 5 },
	"silver":     { "display": "Argent",     "palier": 2, "price": 60,    "mine_time": 2.1, "peak": 42,  "color": Color(0.80, 0.82, 0.86), "atlas_x": 6 },
	"amethyst":   { "display": "Améthyste",  "palier": 2, "price": 74,    "mine_time": 2.2, "peak": 36,  "color": Color(0.60, 0.30, 0.78), "atlas_x": 7 },
	"topaz":      { "display": "Topaze",     "palier": 2, "price": 90,    "mine_time": 2.2, "peak": 30,  "color": Color(0.92, 0.66, 0.18), "atlas_x": 8 },
	"gold":       { "display": "Or",         "palier": 4, "price": 520,   "mine_time": 3.4, "peak": 30,  "color": Color(1.00, 0.80, 0.16), "atlas_x": 9 },
	"emerald":    { "display": "Émeraude",   "palier": 4, "price": 720,   "mine_time": 3.6, "peak": 22,  "color": Color(0.13, 0.70, 0.40), "atlas_x": 10 },
	"sapphire":   { "display": "Saphir",     "palier": 5, "price": 1150,  "mine_time": 4.4, "peak": 18,  "color": Color(0.18, 0.40, 0.88), "atlas_x": 11 },
	"ruby":       { "display": "Rubis",      "palier": 5, "price": 1450,  "mine_time": 4.6, "peak": 14,  "color": Color(0.82, 0.12, 0.24), "atlas_x": 12 },
	"obsidian":   { "display": "Obsidienne", "palier": 6, "price": 1850,  "mine_time": 5.4, "peak": 16,  "color": Color(0.20, 0.16, 0.26), "atlas_x": 13 },
	"diamond":    { "display": "Diamant",    "palier": 6, "price": 2500,  "mine_time": 5.8, "peak": 10,  "color": Color(0.70, 0.92, 0.95), "atlas_x": 14 },
	"platinum":   { "display": "Platine",    "palier": 6, "price": 3000,  "mine_time": 6.0, "peak": 8,   "color": Color(0.74, 0.80, 0.88), "atlas_x": 15 },
	"orichalcum": { "display": "Orichalque", "palier": 7, "price": 4400,  "mine_time": 7.2, "peak": 7,   "color": Color(0.20, 0.66, 0.60), "atlas_x": 16 },
	"adamantite": { "display": "Adamantite", "palier": 7, "price": 5600,  "mine_time": 7.6, "peak": 5,   "color": Color(0.42, 0.10, 0.30), "atlas_x": 17 },
	"mythril":    { "display": "Mythril",    "palier": 8, "price": 10500, "mine_time": 8.6, "peak": 4,   "color": Color(0.62, 0.86, 0.92), "atlas_x": 18 },
	"etherium":   { "display": "Étherium",   "palier": 8, "price": 14000, "mine_time": 9.0, "peak": 3,   "color": Color(0.74, 0.32, 0.92), "atlas_x": 19 },
}

# palier (1..8) → couche géologique : tuile matériau (atlas tileset.png), temps de
# minage de la roche nue, et nom d'affichage. Le bedrock ferme le fond.
const LAYERS: Dictionary = {
	1: { "tile": Vector2i(0, 0), "rock_time": 0.48, "display": "Terre" },
	2: { "tile": Vector2i(1, 0), "rock_time": 0.96, "display": "Roche" },
	3: { "tile": Vector2i(2, 0), "rock_time": 1.70, "display": "Roche profonde" },
	4: { "tile": Vector2i(3, 0), "rock_time": 2.60, "display": "Granit" },
	5: { "tile": Vector2i(6, 0), "rock_time": 3.60, "display": "Basalte" },
	6: { "tile": Vector2i(7, 0), "rock_time": 4.80, "display": "Schiste sombre" },
	7: { "tile": Vector2i(4, 0), "rock_time": 6.20, "display": "Volcanique" },
	8: { "tile": Vector2i(8, 0), "rock_time": 8.00, "display": "Noyau" },
}
const BEDROCK_TILE: Vector2i = Vector2i(5, 0)
const BEDROCK_TIME: float    = 9999.0

# ─────────────────────────────────────────────────────────────────────────────
#  ACCESSEURS MINERAIS
# ─────────────────────────────────────────────────────────────────────────────

func get_ids() -> Array:
	return ORES.keys()

func has_ore(id: String) -> bool:
	return ORES.has(id)

func get_display(id: String) -> String:
	if ORES.has(id):
		return ORES[id]["display"]
	return id.capitalize()

func get_price(id: String) -> int:
	return int(ORES.get(id, {}).get("price", 0))

func get_palier(id: String) -> int:
	return int(ORES.get(id, {}).get("palier", 1))

func get_mine_time(id: String) -> float:
	return float(ORES.get(id, {}).get("mine_time", 1.0))

func get_color(id: String) -> Color:
	return ORES.get(id, {}).get("color", Color.WHITE)

func get_atlas(id: String) -> Vector2i:
	return Vector2i(int(ORES.get(id, {}).get("atlas_x", 0)), 0)

# Dictionnaire { id: prix } pour initialiser le marché.
func get_base_prices() -> Dictionary:
	var prices: Dictionary = {}
	for id in ORES:
		prices[id] = ORES[id]["price"]
	return prices

# Rendement d'un minerai dans une couche donnée (1 à son palier de spawn).
func get_yield(id: String, palier: int) -> int:
	return maxi(1, palier - get_palier(id) + 1)

# ─────────────────────────────────────────────────────────────────────────────
#  ACCESSEURS COUCHES
# ─────────────────────────────────────────────────────────────────────────────

func layer_tile(palier: int) -> Vector2i:
	return LAYERS.get(clampi(palier, 1, N_PALIERS), LAYERS[1])["tile"]

func layer_time(palier: int) -> float:
	return float(LAYERS.get(clampi(palier, 1, N_PALIERS), LAYERS[1])["rock_time"])

func layer_display(palier: int) -> String:
	return LAYERS.get(clampi(palier, 1, N_PALIERS), LAYERS[1])["display"]

# Palier (1..8) correspondant à une tuile matériau, pour retrouver le rendement.
func palier_of_tile(tile: Vector2i) -> int:
	for p in LAYERS:
		if LAYERS[p]["tile"] == tile:
			return int(p)
	return 1

# ─────────────────────────────────────────────────────────────────────────────
#  ABONDANCE & TIRAGE
# ─────────────────────────────────────────────────────────────────────────────

# Poids d'abondance d'un minerai dans la couche L (0 s'il n'y apparaît pas).
func ore_weight(id: String, palier: int) -> float:
	var spawn: int = get_palier(id)
	var peak: float = float(ORES.get(id, {}).get("peak", 1))
	if palier == spawn - 1:
		return peak * LEAK_FACTOR
	if palier >= spawn:
		return peak * pow(DEEP_DECAY, float(palier - spawn))
	return 0.0

# Liste des minerais pouvant apparaître dans la couche L : [ [id, poids], … ]
func layer_pool(palier: int) -> Array:
	var pool: Array = []
	for id in ORES:
		var w: float = ore_weight(id, palier)
		if w > 0.0:
			pool.append([id, w])
	return pool

# Tire un minerai pondéré dans le pool d'une couche, restreint à un sous-ensemble
# autorisé (allowed) si fourni. Renvoie "" si le pool est vide.
func pick_ore(palier: int, rng: RandomNumberGenerator, allowed: Dictionary = {}) -> String:
	var pool: Array = layer_pool(palier)
	var total: float = 0.0
	for entry in pool:
		if allowed.is_empty() or allowed.has(entry[0]):
			total += float(entry[1])
	if total <= 0.0:
		return ""
	var roll: float = rng.randf() * total
	for entry in pool:
		if not allowed.is_empty() and not allowed.has(entry[0]):
			continue
		roll -= float(entry[1])
		if roll <= 0.0:
			return entry[0]
	return ""

# Minerai le plus rare (palier le plus élevé) d'un ensemble présent.
func rarest_of(present: Array) -> String:
	var best: String = ""
	var best_p: int = -1
	for id in present:
		var p: int = get_palier(id)
		if p > best_p:
			best_p = p
			best = id
	return best

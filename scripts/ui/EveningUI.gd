extends Control

# ─────────────────────────────────────────────────────────────────────────────
#  EveningUI.gd  —  Phase du soir (onglets Marché / Améliorations)
#
#  Onglet MARCHÉ   : cours du marché + coffre (à vider) + stockage loué.
#  Onglet AMÉLIORATIONS : arbre de recherche.
#  Barre du bas fixe : bouton « Lancer la journée suivante » + aide.
#
#  Le coffre (butin du jour) doit être VIDÉ pour continuer : chaque unité est
#  vendue ou déplacée en stockage. Le stockage persiste contre un loyer/nuit.
# ─────────────────────────────────────────────────────────────────────────────

const RES_ORDER: Array[String] = ["coal", "iron", "gold", "gem", "crystal"]
const RES_NAMES: Dictionary = {
	"coal": "Charbon", "iron": "Fer", "gold": "Or", "gem": "Gemmes", "crystal": "Cristaux",
}
const CAT_NAMES: Dictionary = {
	ResearchNode.Category.MINING:       "⛏  Minage",
	ResearchNode.Category.EXPLOSIVES:   "💥  Explosifs",
	ResearchNode.Category.LOGISTICS:    "📦  Logistique",
	ResearchNode.Category.PROCESSING:   "🏭  Traitement",
	ResearchNode.Category.INTELLIGENCE: "🔍  Renseignement",
}

const COL_UP:   Color = Color(0.45, 0.9, 0.5)
const COL_DOWN: Color = Color(0.95, 0.45, 0.45)
const COL_FLAT: Color = Color(0.7, 0.7, 0.7)

@onready var day_label:    Label         = $TopBar/TopRow/DayLabel
@onready var money_label:  Label         = $TopBar/TopRow/MoneyLabel
@onready var rent_label:   Label         = $TopBar/TopRow/RentLabel
@onready var tabs:         TabContainer  = $Tabs
@onready var market_scroll: ScrollContainer = $Tabs/MarketTab
@onready var market_box:   VBoxContainer = $Tabs/MarketTab/MarketMargin/MarketContent
@onready var upg_scroll:   ScrollContainer = $Tabs/UpgradesTab
@onready var tree_canvas:  Control       = $Tabs/UpgradesTab/TreeCanvas
@onready var help_label:   Label         = $BottomBar/BottomRow/HelpLabel
@onready var next_day_btn: Button        = $BottomBar/BottomRow/NextDayButton

var _sold: Dictionary = {}   # quantités vendues ce soir par le joueur

func _corp() -> CorporationData:
	return GameManager.player_corporation

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for r in RES_ORDER:
		_sold[r] = 0

	tabs.set_tab_title(0, "  Marché  ")
	tabs.set_tab_title(1, "  Améliorations  ")

	day_label.add_theme_font_size_override("font_size", 20)
	money_label.add_theme_font_size_override("font_size", 20)
	money_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6))

	day_label.text = "Soir — Jour %d" % GameManager.current_day
	next_day_btn.pressed.connect(_on_next_day)

	# Garde-fou : si la scène est lancée seule (sans partie démarrée), pas de corp.
	if _corp() == null:
		help_label.text = "Aucune partie en cours — lance le jeu via Main.tscn."
		next_day_btn.disabled = true
		return

	_refresh()

# ─────────────────────────────────────────────────────────────────────────────
#  RAFRAÎCHISSEMENT
# ─────────────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	var sv_m: int = market_scroll.scroll_vertical
	var sv_u: int = upg_scroll.scroll_vertical
	var sh_u: int = upg_scroll.scroll_horizontal

	var corp := _corp()
	money_label.text = "Argent : %d$" % corp.money
	rent_label.text  = "Loyer/nuit : %d$" % corp.storage_rent()

	_build_market_tab()
	_build_upgrades_tab()
	_update_gate()

	# Restaure la position de défilement (évite les sauts après chaque action)
	market_scroll.set_deferred("scroll_vertical", sv_m)
	upg_scroll.set_deferred("scroll_vertical", sv_u)
	upg_scroll.set_deferred("scroll_horizontal", sh_u)

# ─── Onglet MARCHÉ ────────────────────────────────────────────────────────────

func _build_market_tab() -> void:
	for c in market_box.get_children():
		c.queue_free()
	_build_prices_card()
	_build_chest_card()
	_build_storage_card()

func _build_prices_card() -> void:
	var box := _card(market_box, "COURS DU MARCHÉ")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	for res in RES_ORDER:
		var n := Label.new()
		n.text = RES_NAMES[res]
		n.custom_minimum_size = Vector2(120, 0)
		grid.add_child(n)

		var p := Label.new()
		p.text = "%d$" % MarketManager.get_price(res)
		p.custom_minimum_size = Vector2(70, 0)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(p)

		var trend: int = MarketManager.get_price_trend(res)
		var t := Label.new()
		t.text = MarketManager.get_trend_icon(res)
		t.add_theme_color_override("font_color",
			COL_UP if trend > 0 else (COL_DOWN if trend < 0 else COL_FLAT))
		grid.add_child(t)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(spacer)
	box.add_child(grid)

func _build_chest_card() -> void:
	var corp := _corp()
	var box := _card(market_box, "COFFRE — à vider ce soir")
	var empty := true
	for res in RES_ORDER:
		var qty: int = corp.inventory.get(res, 0)
		if qty > 0:
			empty = false
		box.add_child(_resource_row(res, qty, true))

	var sell_all := Button.new()
	sell_all.text = "Tout vendre"
	sell_all.disabled = empty
	sell_all.pressed.connect(_on_sell_all_chest)
	box.add_child(sell_all)

func _build_storage_card() -> void:
	var corp := _corp()
	var box := _card(market_box, "STOCKAGE")

	var info := Label.new()
	info.text = "Capacité : %d / %d unités     Loyer : %d$/nuit" % [
		corp.storage_used(), corp.storage_capacity(), corp.storage_rent()]
	box.add_child(info)

	# Boutons de location
	var rent_bar := HBoxContainer.new()
	rent_bar.add_theme_constant_override("separation", 6)
	var prompt := Label.new()
	prompt.text = "Louer :"
	rent_bar.add_child(prompt)
	for unit_id in CorporationData.STORAGE_UNITS:
		var u: Dictionary = CorporationData.STORAGE_UNITS[unit_id]
		var b := Button.new()
		var locked: bool = (unit_id == "medium" and not corp.has_research("storage_2")) \
			or (unit_id == "large" and not corp.has_research("storage_3"))
		if locked:
			var req: String = "Entrepôt II" if unit_id == "medium" else "Entrepôt III"
			b.text = "🔒 %s (%s)" % [u["name"], req]
			b.disabled = true
		else:
			b.text = "%s (%du · %d$)" % [u["name"], u["capacity"], u["rent"]]
			b.pressed.connect(_on_rent_unit.bind(unit_id))
		rent_bar.add_child(b)
	box.add_child(rent_bar)

	# Unités louées (résiliation)
	for unit_id in corp.rented_storage:
		var u: Dictionary = CorporationData.STORAGE_UNITS[unit_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.custom_minimum_size = Vector2(260, 0)
		lbl.text = "• %s — %d u, %d$/nuit" % [u["name"], u["capacity"], u["rent"]]
		row.add_child(lbl)
		var cancel := Button.new()
		cancel.text = "Résilier"
		cancel.disabled = corp.storage_used() > corp.storage_capacity() - int(u["capacity"])
		cancel.pressed.connect(_on_cancel_unit.bind(unit_id))
		row.add_child(cancel)
		box.add_child(row)

	# Ressources entreposées (vendre)
	var has_stored := false
	for res in RES_ORDER:
		if corp.storage.get(res, 0) > 0:
			has_stored = true
			box.add_child(_resource_row(res, corp.storage[res], false))
	if not has_stored and not corp.rented_storage.is_empty():
		var hint := Label.new()
		hint.text = "Stockage vide — dépose des ressources depuis le coffre."
		hint.add_theme_color_override("font_color", COL_FLAT)
		box.add_child(hint)

# Ligne d'une ressource. from_chest = true → boutons Vendre + Stocker ; sinon Vendre (depuis stockage).
func _resource_row(res: String, qty: int, from_chest: bool) -> HBoxContainer:
	var corp := _corp()
	var price: int = MarketManager.get_sell_price(res, corp)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(300, 0)
	lbl.text = "%s ×%d    @%d$ %s    = %d$" % [
		RES_NAMES[res], qty, price, MarketManager.get_trend_icon(res), qty * price]
	row.add_child(lbl)

	var sell := Button.new()
	sell.text = "Vendre"
	sell.disabled = qty <= 0
	if from_chest:
		sell.pressed.connect(_on_sell_chest.bind(res))
	else:
		sell.pressed.connect(_on_sell_storage.bind(res))
	row.add_child(sell)

	if from_chest:
		var store := Button.new()
		store.text = "→ Stocker"
		store.disabled = qty <= 0 or corp.storage_room() <= 0
		store.pressed.connect(_on_store.bind(res))
		row.add_child(store)
	return row

# ─── Onglet AMÉLIORATIONS ─────────────────────────────────────────────────────

# ─── Onglet AMÉLIORATIONS (arbre visuel) ──────────────────────────────────────

const CELL_W:    int = 232
const CELL_H:    int = 132
const CARD_W:    int = 206
const CARD_H:    int = 104
const TREE_PAD:  int = 18

const COL_OWNED:  Color = Color(0.40, 0.85, 0.45)
const COL_AFFORD: Color = Color(0.40, 0.75, 1.00)
const COL_POOR:   Color = Color(0.85, 0.55, 0.35)
const COL_LOCKED: Color = Color(0.45, 0.45, 0.48)
const COL_COMING: Color = Color(0.35, 0.35, 0.40)
const COL_LINE_ON:  Color = Color(0.40, 0.85, 0.45, 0.9)
const COL_LINE_OFF: Color = Color(0.5, 0.5, 0.55, 0.5)

func _build_upgrades_tab() -> void:
	for c in tree_canvas.get_children():
		c.queue_free()
	var corp := _corp()
	var nodes: Array = ResearchManager.get_all_nodes()

	# 1) Traits de prérequis (ajoutés d'abord → derrière les cases)
	var max_col: int = 0
	var max_row: int = 0
	for node: ResearchNode in nodes:
		max_col = maxi(max_col, node.tree_pos.x)
		max_row = maxi(max_row, node.tree_pos.y)
		for pr in node.prerequisites:
			var pn: ResearchNode = ResearchManager.get_research_node(pr)
			if pn == null:
				continue
			var line := Line2D.new()
			line.width = 3.0
			line.default_color = COL_LINE_ON if corp.has_research(pr) else COL_LINE_OFF
			line.add_point(_node_center(pn))
			line.add_point(_node_center(node))
			tree_canvas.add_child(line)

	# 2) Cases des nœuds (par-dessus les traits)
	for node: ResearchNode in nodes:
		tree_canvas.add_child(_make_node_card(node, corp))

	tree_canvas.custom_minimum_size = Vector2(
		(max_col + 1) * CELL_W + TREE_PAD * 2,
		(max_row + 1) * CELL_H + TREE_PAD * 2)

func _node_center(node: ResearchNode) -> Vector2:
	return Vector2(
		node.tree_pos.x * CELL_W + TREE_PAD + CARD_W / 2.0,
		node.tree_pos.y * CELL_H + TREE_PAD + CARD_H / 2.0)

func _make_node_card(node: ResearchNode, corp: CorporationData) -> Control:
	var level: int = corp.get_research_level(node.id)
	var maxed: bool = level >= node.max_level
	var cost: int  = node.get_total_cost(level)

	var prereqs_met: bool = true
	var missing: String = ""
	for pr in node.prerequisites:
		if not corp.has_research(pr):
			prereqs_met = false
			var pn: ResearchNode = ResearchManager.get_research_node(pr)
			missing = pn.display_name if pn else pr
			break

	# État → couleur + texte de statut
	var border: Color = COL_LOCKED
	var status: String = ""
	if node.coming_soon:
		border = COL_COMING
		status = "à venir"
	elif maxed:
		border = COL_OWNED
		status = "✓ acquis" if node.max_level == 1 else "✓ max (%d/%d)" % [level, node.max_level]
	elif not prereqs_met:
		border = COL_LOCKED
		status = "🔒 %s" % missing
	elif corp.can_afford(cost):
		border = COL_AFFORD
		status = "Acheter — %d$" % cost
	else:
		border = COL_POOR
		status = "%d$ (insuffisant)" % cost

	var lvl_txt: String = ""
	if node.max_level > 1 and not node.coming_soon:
		lvl_txt = "  [%d/%d]" % [level, node.max_level]

	# Carte
	var card := PanelContainer.new()
	card.position = Vector2(node.tree_pos.x * CELL_W + TREE_PAD, node.tree_pos.y * CELL_H + TREE_PAD)
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = node.description
	card.gui_input.connect(_on_node_input.bind(node.id))

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.16, 0.95)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	card.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)

	var title := Label.new()
	title.text = node.display_name + lvl_txt
	title.add_theme_font_size_override("font_size", 15)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if node.coming_soon:
		title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vb.add_child(title)

	var st := Label.new()
	st.text = status
	st.add_theme_font_size_override("font_size", 12)
	st.add_theme_color_override("font_color", border)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(st)

	return card

func _on_node_input(event: InputEvent, node_id: String) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if ResearchManager.can_research(node_id, _corp()):
			ResearchManager.research(node_id, _corp())
			_refresh()

# ─── Carte (panneau stylé avec titre) ─────────────────────────────────────────

func _card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.045)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	if title != "":
		var h := Label.new()
		h.text = title
		h.add_theme_font_size_override("font_size", 17)
		vb.add_child(h)
		var sep := HSeparator.new()
		vb.add_child(sep)

	parent.add_child(panel)
	return vb

# ─── Barre du bas / gating ────────────────────────────────────────────────────

func _update_gate() -> void:
	var corp := _corp()
	var chest_empty: bool = true
	for res in RES_ORDER:
		if corp.inventory.get(res, 0) > 0:
			chest_empty = false
			break
	var can_pay_rent: bool = corp.money >= corp.storage_rent()

	next_day_btn.disabled = not chest_empty or not can_pay_rent
	if not chest_empty:
		help_label.text = "Vide ton coffre (vends ou déplace en stockage) pour continuer."
		help_label.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	elif not can_pay_rent:
		help_label.text = "Tu ne peux pas payer le loyer du stockage — vends ou résilie."
		help_label.add_theme_color_override("font_color", COL_DOWN)
	else:
		help_label.text = "Coffre vide — prêt à lancer la journée."
		help_label.add_theme_color_override("font_color", COL_UP)

# ─────────────────────────────────────────────────────────────────────────────
#  ACTIONS
# ─────────────────────────────────────────────────────────────────────────────

func _on_sell_chest(res: String) -> void:
	var corp := _corp()
	var qty: int = corp.inventory.get(res, 0)
	if qty <= 0:
		return
	corp.earn(qty * MarketManager.get_sell_price(res, corp))
	_sold[res] += qty
	corp.inventory[res] = 0
	_refresh()

func _on_sell_all_chest() -> void:
	for res in RES_ORDER:
		_on_sell_chest(res)

func _on_store(res: String) -> void:
	var corp := _corp()
	var qty: int = corp.inventory.get(res, 0)
	if qty <= 0:
		return
	var put: int = corp.add_to_storage(res, qty)
	corp.inventory[res] = qty - put
	_refresh()

func _on_sell_storage(res: String) -> void:
	var corp := _corp()
	var qty: int = corp.storage.get(res, 0)
	if qty <= 0:
		return
	corp.earn(qty * MarketManager.get_sell_price(res, corp))
	_sold[res] += qty
	corp.storage[res] = 0
	_refresh()

func _on_rent_unit(unit_id: String) -> void:
	_corp().rent_unit(unit_id)
	_refresh()

func _on_cancel_unit(unit_id: String) -> void:
	_corp().cancel_unit(unit_id)
	_refresh()

func _on_buy_research(node_id: String) -> void:
	ResearchManager.research(node_id, _corp())
	_refresh()

func _on_next_day() -> void:
	next_day_btn.disabled = true
	GameManager.close_evening(_sold)
	get_tree().change_scene_to_file.call_deferred("res://scenes/UI/BiddingUI.tscn")

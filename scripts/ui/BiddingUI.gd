extends VBoxContainer

# ─────────────────────────────────────────────────────────────────────────────
#  BiddingUI.gd
#  Pilote l'enchère temps réel (BiddingManager).
#
#  Réutilise la structure de scène existante (BiddingUI.tscn) — les boutons sont
#  simplement reciblés :
#    ConfirmBidButton → "Cibler / Relancer"
#    ClearBidButton   → "Lâcher la parcelle"
#    ConfirmAllButton → "Valider"
#    BidSlider        → mise max du joueur
# ─────────────────────────────────────────────────────────────────────────────

var ParcelCardScene: PackedScene

# ─── Références UI ────────────────────────────────────────────────────────────
@onready var day_label:          Label          = $TopBar/DayLabel
@onready var timer_label:        Label          = $TopBar/TimerLabel
@onready var budget_label:       Label          = $TopBar/BudgetLabel
@onready var parcel_grid:        GridContainer  = $MainLayout/LeftPanel/ParcelGrid
@onready var public_card_slot:   Control        = $MainLayout/LeftPanel/PublicParcelBox/PublicCardSlot
@onready var bid_panel:          PanelContainer = $MainLayout/RightPanel/BidPanel
@onready var parcel_title:       Label          = $MainLayout/RightPanel/BidPanel/VBoxContainer/ParcelTitle
@onready var type_warning:       Label          = $MainLayout/RightPanel/BidPanel/VBoxContainer/TypeWarning
@onready var bid_amount_label:   Label          = $MainLayout/RightPanel/BidPanel/VBoxContainer/BidAmountLabel
@onready var bid_slider:         HSlider        = $MainLayout/RightPanel/BidPanel/VBoxContainer/BidSlider
@onready var confirm_bid_button: Button         = $MainLayout/RightPanel/BidPanel/VBoxContainer/ConfirmBidButton
@onready var clear_bid_button:   Button         = $MainLayout/RightPanel/BidPanel/VBoxContainer/ClearBidButton
@onready var validate_button:    Button         = $BottomBar/ConfirmAllButton
@onready var help_label:         Label          = $BottomBar/HelpLabel
@onready var corps_panel:        VBoxContainer  = $MainLayout/RightPanel/CorpsPanel

# ─── État local ───────────────────────────────────────────────────────────────
var selected_parcel: ParcelData = null
var parcel_cards: Dictionary = {}     # parcel_id -> ParcelCard
var _validating: bool = false
var _flash_active: bool = false

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ParcelCardScene = load("res://scenes/UI/ParcelCard.tscn")
	bid_panel.hide()

	# Signaux du moteur d'enchères
	BiddingManager.auction_started.connect(_on_auction_started)
	BiddingManager.board_changed.connect(_on_board_changed)
	BiddingManager.time_updated.connect(_on_time_updated)
	BiddingManager.settled_changed.connect(_on_settled_changed)
	BiddingManager.player_outbid.connect(_on_player_outbid)
	BiddingManager.auction_validated.connect(_on_auction_validated)

	# Boutons reciblés
	confirm_bid_button.text = "Cibler / Relancer"
	clear_bid_button.text   = "Lâcher la parcelle"
	validate_button.text    = "Valider"
	confirm_bid_button.pressed.connect(_on_confirm_pressed)
	clear_bid_button.pressed.connect(_on_clear_pressed)
	validate_button.pressed.connect(_on_validate_pressed)

	day_label.text = "Jour %d" % GameManager.current_day

	if BiddingManager.active:
		_on_auction_started()

# ─────────────────────────────────────────────────────────────────────────────
#  DÉMARRAGE
# ─────────────────────────────────────────────────────────────────────────────

func _on_auction_started() -> void:
	_validating = false
	selected_parcel = null
	bid_panel.hide()
	_populate_parcels()
	_on_board_changed()

func _populate_parcels() -> void:
	for child in parcel_grid.get_children():
		child.queue_free()
	for child in public_card_slot.get_children():
		child.queue_free()
	parcel_cards.clear()

	for parcel in GameManager.current_parcels:
		var card: Node = ParcelCardScene.instantiate()
		if parcel.is_public:
			public_card_slot.add_child(card)
		else:
			parcel_grid.add_child(card)
		card.setup(parcel)
		card.parcel_selected.connect(_on_parcel_selected)
		parcel_cards[parcel.parcel_id] = card

# ─────────────────────────────────────────────────────────────────────────────
#  SÉLECTION
# ─────────────────────────────────────────────────────────────────────────────

func _on_parcel_selected(parcel: ParcelData) -> void:
	if _validating or parcel.is_public:
		return
	selected_parcel = parcel
	_refresh_bid_panel()
	bid_panel.show()

func _refresh_bid_panel() -> void:
	if not selected_parcel:
		return
	var pid: int = selected_parcel.parcel_id

	parcel_title.text = selected_parcel.get_display_name()
	_set_info_label("SolValue",        selected_parcel.get_soil_display())
	_set_info_label("ProfondeurValue", selected_parcel.get_depth_display())
	_set_info_label("RessourceValue",  selected_parcel.get_resource_display())
	_set_info_label("PrixValue",       "%d$" % selected_parcel.base_price)

	type_warning.text    = _get_type_warning(selected_parcel)
	type_warning.visible = type_warning.text != ""

	var cost: int = BiddingManager.get_cost_to_take(pid)
	var money: int = GameManager.player_corporation.money
	var is_current: bool = BiddingManager.get_player_target() == pid

	bid_slider.min_value = cost
	bid_slider.max_value = maxi(money, cost)
	bid_slider.step      = 5
	var default_val: int = BiddingManager.player_target_max if is_current else cost
	bid_slider.value     = clampi(default_val, cost, int(bid_slider.max_value))

	if not bid_slider.value_changed.is_connected(_on_slider_changed):
		bid_slider.value_changed.connect(_on_slider_changed)
	_on_slider_changed(bid_slider.value)

func _get_type_warning(parcel: ParcelData) -> String:
	match parcel.parcel_type:
		ParcelData.ParcelType.MYSTERY:  return "⚠ Infos cachées. Jackpot ou vide total !"
		ParcelData.ParcelType.UNSTABLE: return "⚠ Risque d'effondrement pendant la mine"
		ParcelData.ParcelType.RESERVED:
			var has: bool = GameManager.player_corporation.has_research(parcel.required_research)
			return "🔒 Requiert : %s" % parcel.required_research if not has else \
				   "✓ Recherche débloquée — tu peux enchérir"
	return ""

func _set_info_label(node_name: String, value: String) -> void:
	var label := bid_panel.find_child(node_name, true, false) as Label
	if label:
		label.text = value

# ─────────────────────────────────────────────────────────────────────────────
#  ACTIONS DU JOUEUR
# ─────────────────────────────────────────────────────────────────────────────

func _on_slider_changed(value: float) -> void:
	if not selected_parcel:
		return
	var cost: int = BiddingManager.get_cost_to_take(selected_parcel.parcel_id)
	bid_amount_label.text = "Mise max : %d$   (coût actuel : %d$)" % [int(value), cost]

func _on_confirm_pressed() -> void:
	if not selected_parcel:
		return
	var ok: bool = BiddingManager.set_player_target(selected_parcel.parcel_id, int(bid_slider.value))
	if ok:
		_refresh_bid_panel()
	else:
		bid_amount_label.text       = "Mise trop basse ou fonds insuffisants !"
		bid_amount_label.modulate   = Color.RED
		await get_tree().create_timer(1.0).timeout
		bid_amount_label.modulate   = Color.WHITE
		_on_slider_changed(bid_slider.value)

func _on_clear_pressed() -> void:
	BiddingManager.clear_player_target()
	bid_panel.hide()
	selected_parcel = null

func _on_validate_pressed() -> void:
	if not BiddingManager.is_settled():
		return
	_validating = true
	validate_button.disabled = true
	BiddingManager.validate()

# ─────────────────────────────────────────────────────────────────────────────
#  RAFRAÎCHISSEMENT
# ─────────────────────────────────────────────────────────────────────────────

func _on_board_changed() -> void:
	for pid: int in parcel_cards:
		var card: Node = parcel_cards[pid]
		var holder_id: int = BiddingManager.get_holder(pid)
		var col: Color = Color.GRAY
		if holder_id > 0:
			var corp: CorporationData = GameManager.get_corp_by_id(holder_id)
			if corp:
				col = corp.color
		var is_my_target: bool = (holder_id == 0)
		card.set_auction_state(BiddingManager.get_bid(pid), holder_id, col, is_my_target)

	_refresh_corps_panel()
	_update_budget()
	_refresh_status()
	if selected_parcel:
		_on_slider_changed(bid_slider.value)

func _update_budget() -> void:
	var money: int     = GameManager.player_corporation.money
	var committed: int = BiddingManager.get_player_committed()
	budget_label.text = "Argent : %d$   (engagé : %d$)" % [money, committed]

func _on_time_updated(time_left: float) -> void:
	var secs: int = maxi(0, int(time_left))
	timer_label.text     = "%d:%02d" % [secs / 60, secs % 60]
	timer_label.modulate = Color.RED if time_left <= 10 else \
						   Color.YELLOW if time_left <= 20 else Color.WHITE

func _on_settled_changed(settled: bool) -> void:
	validate_button.disabled = not settled or _validating

func _on_player_outbid(pid: int) -> void:
	var card: Node = parcel_cards.get(pid)
	if card:
		var tw := create_tween()
		tw.tween_property(card, "modulate", Color(1.8, 0.5, 0.5), 0.1)
		tw.tween_property(card, "modulate", Color.WHITE, 0.5)
	_flash_active = true
	help_label.text     = "⚠ Tu t'es fait souffler une parcelle !"
	help_label.modulate = Color.RED
	await get_tree().create_timer(1.3).timeout
	_flash_active = false
	help_label.modulate = Color.WHITE
	_refresh_status()

func _refresh_status() -> void:
	if _flash_active:
		return
	var homeless: int = BiddingManager.get_homeless_ai_count()
	if homeless > 0:
		help_label.text = "Enchères en cours — compagnies sans parcelle : %d" % homeless
	elif BiddingManager.get_player_target() == -1:
		help_label.text = "Choisis ta parcelle !"
	else:
		help_label.text = "Tout le monde est placé — valide quand tu veux."

func _refresh_corps_panel() -> void:
	for child in corps_panel.get_children():
		child.queue_free()
	for corp in GameManager.get_all_corporations():
		var pid: int = BiddingManager.get_company_parcel_id(corp.corp_id)
		var where: String = "—"
		if pid != -1:
			var p: ParcelData = GameManager.get_parcel_by_id(pid)
			where = p.get_display_name() if p else "?"
		var label := Label.new()
		label.text     = "%s  —  %d$   [%s]" % [corp.corp_name, corp.money, where]
		label.modulate = corp.color
		corps_panel.add_child(label)

# ─────────────────────────────────────────────────────────────────────────────
#  VALIDATION → MINE
# ─────────────────────────────────────────────────────────────────────────────

func _on_auction_validated() -> void:
	help_label.text = "Parcelles attribuées — descente dans la mine…"
	await get_tree().create_timer(1.2).timeout
	GameManager.start_mining_phase()
	get_tree().change_scene_to_file.call_deferred("res://scenes/World.tscn")

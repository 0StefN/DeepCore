extends VBoxContainer

# ─────────────────────────────────────────────────────────────────────────────
#  BiddingUI.gd
#  Contrôle l'interface de la phase d'enchères.
#
#  Structure de scène attendue (BiddingUI.tscn) :
#
#  BiddingUI (Control, plein écran)
#  ├── Background (ColorRect)
#  ├── TopBar (HBoxContainer)
#  │   ├── DayLabel (Label)           "Jour 3"
#  │   ├── TimerLabel (Label)         "0:48"
#  │   └── BudgetLabel (Label)        "Budget : 650$ / 1000$"
#  ├── MainLayout (HBoxContainer)
#  │   ├── LeftPanel (VBoxContainer)  — Grille des parcelles
#  │   │   ├── PublicParcelBox (VBoxContainer)
#  │   │   │   ├── PublicLabel (Label) "Parcelle publique (gratuite)"
#  │   │   │   └── PublicCardSlot (Control) ← carte injectée dynamiquement
#  │   │   ├── Separator (HSeparator)
#  │   │   └── ParcelGrid (GridContainer, columns=4)
#  │   └── RightPanel (VBoxContainer) — Panneau de mise
#  │       ├── BidPanel (PanelContainer)
#  │       │   ├── ParcelTitle (Label)
#  │       │   ├── InfoGrid (GridContainer, columns=2)
#  │       │   │   ├── (Labels: Sol / Profondeur / Ressource / Type / Prix de base)
#  │       │   ├── TypeWarning (Label)
#  │       │   ├── BidAmountLabel (Label)   "Votre offre : 200$"
#  │       │   ├── BidSlider (HSlider)
#  │       │   ├── ConfirmBidButton (Button)
#  │       │   └── ClearBidButton (Button)
#  │       └── CorpsPanel (VBoxContainer)  — Scores des corps
#  └── BottomBar (HBoxContainer)
#      ├── HelpLabel (Label)
#      └── ConfirmAllButton (Button) "Confirmer et miner →"
# ─────────────────────────────────────────────────────────────────────────────

var ParcelCardScene: PackedScene  # chargé dans _ready() une fois la scène créée

# ─── Références UI ────────────────────────────────────────────────────────────
@onready var day_label:          Label         = $TopBar/DayLabel
@onready var timer_label:        Label         = $TopBar/TimerLabel
@onready var budget_label:       Label         = $TopBar/BudgetLabel
@onready var parcel_grid:        GridContainer = $MainLayout/LeftPanel/ParcelGrid
@onready var public_card_slot:   Control       = $MainLayout/LeftPanel/PublicParcelBox/PublicCardSlot
@onready var bid_panel:          PanelContainer = $MainLayout/RightPanel/BidPanel
@onready var parcel_title:       Label          = $MainLayout/RightPanel/BidPanel/VBoxContainer/ParcelTitle
@onready var type_warning:       Label          = $MainLayout/RightPanel/BidPanel/VBoxContainer/TypeWarning
@onready var bid_amount_label:   Label          = $MainLayout/RightPanel/BidPanel/VBoxContainer/BidAmountLabel
@onready var bid_slider:         HSlider        = $MainLayout/RightPanel/BidPanel/VBoxContainer/BidSlider
@onready var confirm_bid_button: Button         = $MainLayout/RightPanel/BidPanel/VBoxContainer/ConfirmBidButton
@onready var clear_bid_button:   Button         = $MainLayout/RightPanel/BidPanel/VBoxContainer/ClearBidButton
@onready var confirm_all_button: Button        = $BottomBar/ConfirmAllButton
@onready var corps_panel:        VBoxContainer = $MainLayout/RightPanel/CorpsPanel

# ─── État local ───────────────────────────────────────────────────────────────
var selected_parcel: ParcelData = null
var parcel_cards: Dictionary = {}     # { parcel_id -> ParcelCard node }
var _result_phase: bool = false       # True après fin des enchères (phase d'affichage)

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ParcelCardScene = load("res://scenes/UI/ParcelCard.tscn")
	bid_panel.hide()

	# Connexion des signaux autoload
	BiddingManager.bidding_started.connect(_on_bidding_started)
	BiddingManager.time_updated.connect(_on_time_updated)
	BiddingManager.bid_updated.connect(_on_bid_updated)
	BiddingManager.bidding_ended.connect(_on_bidding_ended)

	# Boutons
	confirm_bid_button.pressed.connect(_on_confirm_bid_pressed)
	clear_bid_button.pressed.connect(_on_clear_bid_pressed)
	confirm_all_button.pressed.connect(_on_confirm_all_pressed)
	bid_slider.value_changed.connect(_on_slider_changed)

	day_label.text = "Jour %d" % GameManager.current_day
	
	if BiddingManager.bidding_active:
		_on_bidding_started()

# ─────────────────────────────────────────────────────────────────────────────
#  DÉMARRAGE
# ─────────────────────────────────────────────────────────────────────────────

func _on_bidding_started() -> void:
	_result_phase = false
	_populate_parcels()
	_refresh_corps_panel()
	_update_budget_display()
	confirm_all_button.disabled = false
	confirm_all_button.text = "Confirmer et miner →"

func _populate_parcels() -> void:
	# Nettoyer la grille
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
#  SÉLECTION D'UNE PARCELLE
# ─────────────────────────────────────────────────────────────────────────────

func _on_parcel_selected(parcel: ParcelData) -> void:
	if _result_phase:
		return
	selected_parcel = parcel
	_refresh_bid_panel()
	bid_panel.show()

func _refresh_bid_panel() -> void:
	if not selected_parcel:
		return

	parcel_title.text = selected_parcel.get_display_name()

	# Remplir les labels d'info (cherchez-les dans InfoGrid par nom)
	_set_info_label("SolValue",        selected_parcel.get_soil_display())
	_set_info_label("ProfondeurValue", selected_parcel.get_depth_display())
	_set_info_label("RessourceValue",  selected_parcel.get_resource_display())
	_set_info_label("PrixValue",       "%d$" % selected_parcel.base_price)

	# Avertissement de type
	type_warning.text = _get_type_warning(selected_parcel)
	type_warning.visible = type_warning.text != ""

	# Configurer le slider
	var current_bid: int = BiddingManager.get_player_bid(selected_parcel.parcel_id)
	var max_budget:  int = BiddingManager.get_player_remaining_budget() + current_bid
	var min_bid:     int = selected_parcel.base_price if selected_parcel.base_price > 0 else 0

	bid_slider.min_value = min_bid
	bid_slider.max_value = max(max_budget, min_bid)
	bid_slider.step      = 5
	bid_slider.value     = max(current_bid, min_bid)
	_on_slider_changed(bid_slider.value)

func _get_type_warning(parcel: ParcelData) -> String:
	match parcel.parcel_type:
		ParcelData.ParcelType.MYSTERY:   return "⚠ Infos cachées. Jackpot ou vide total !"
		ParcelData.ParcelType.UNSTABLE:  return "⚠ Risque d'effondrement pendant la mine"
		ParcelData.ParcelType.CONTESTED: return "⚔ Les 2 plus offrants peuvent miner ici"
		ParcelData.ParcelType.RESERVED:
			var has: bool = GameManager.player_corporation.has_research(parcel.required_research)
			return "🔒 Requiert : %s" % parcel.required_research if not has else \
				   "✓ Recherche débloquée — vous pouvez enchérir"
	return ""

# Helper : trouve un Label enfant par nom dans InfoGrid
func _set_info_label(node_name: String, value: String) -> void:
	var label := bid_panel.find_child(node_name, true, false) as Label
	if label:
		label.text = value

# ─────────────────────────────────────────────────────────────────────────────
#  ACTIONS DU JOUEUR
# ─────────────────────────────────────────────────────────────────────────────

func _on_slider_changed(value: float) -> void:
	bid_amount_label.text = "Votre offre : %d$" % int(value)

func _on_confirm_bid_pressed() -> void:
	if not selected_parcel:
		return
	var amount := int(bid_slider.value)
	if BiddingManager.place_player_bid(selected_parcel.parcel_id, amount):
		_update_budget_display()
		bid_panel.hide()
	else:
		# Feedback d'erreur — budget insuffisant
		bid_amount_label.text = "Budget insuffisant !"
		bid_amount_label.modulate = Color.RED
		await get_tree().create_timer(1.0).timeout
		bid_amount_label.modulate = Color.WHITE
		_on_slider_changed(bid_slider.value)

func _on_clear_bid_pressed() -> void:
	if not selected_parcel:
		return
	BiddingManager.place_player_bid(selected_parcel.parcel_id, 0)
	_update_budget_display()
	bid_panel.hide()

func _on_confirm_all_pressed() -> void:
	confirm_all_button.disabled = true
	BiddingManager.end_bidding()

# ─────────────────────────────────────────────────────────────────────────────
#  MISES À JOUR UI
# ─────────────────────────────────────────────────────────────────────────────

func _on_bid_updated(parcel_id: int, amount: int) -> void:
	_update_budget_display()
	if parcel_id in parcel_cards:
		parcel_cards[parcel_id].update_bid_display(amount)

func _update_budget_display() -> void:
	var remaining: int = BiddingManager.get_player_remaining_budget()
	var total:     int = GameManager.player_corporation.money
	budget_label.text = "Budget : %d$ / %d$" % [remaining, total]
	budget_label.modulate = Color.YELLOW if float(remaining) / float(total) < 0.25 else Color.WHITE

func _on_time_updated(time_left: float) -> void:
	var secs := int(time_left)
	timer_label.text     = "%d:%02d" % [secs / 60, secs % 60]
	timer_label.modulate = Color.RED if time_left <= 10 else \
						   Color.YELLOW if time_left <= 30 else Color.WHITE

func _refresh_corps_panel() -> void:
	for child in corps_panel.get_children():
		child.queue_free()
	for corp in GameManager.get_all_corporations():
		var label := Label.new()
		label.text = "%s  —  %d$" % [corp.corp_name, corp.money]
		label.modulate = corp.color
		corps_panel.add_child(label)

# ─────────────────────────────────────────────────────────────────────────────
#  RÉVÉLATION DES RÉSULTATS
# ─────────────────────────────────────────────────────────────────────────────

func _on_bidding_ended(_results: Dictionary) -> void:
	_result_phase = true
	bid_panel.hide()
	confirm_all_button.text     = "Révélation en cours…"
	confirm_all_button.disabled = true

	var all_parcels: Array[ParcelData] = GameManager.current_parcels.duplicate()
	for parcel: ParcelData in all_parcels:
		await get_tree().create_timer(0.25).timeout
		_reveal_parcel_result(parcel)

	await get_tree().create_timer(3.0).timeout
	
	# Transition directe — plus besoin de passer par Main.gd
	GameManager.start_mining_phase()
	get_tree().change_scene_to_file.call_deferred("res://scenes/World.tscn")

func _reveal_parcel_result(parcel: ParcelData) -> void:
	if parcel.parcel_id not in parcel_cards:
		return
	var card: Node                  = parcel_cards[parcel.parcel_id]
	var player_won: bool            = BiddingManager.player_won_parcel(parcel.parcel_id)
	var winner_id:  int             = BiddingManager.get_winner_id(parcel.parcel_id)
	card.show_result(player_won, winner_id)

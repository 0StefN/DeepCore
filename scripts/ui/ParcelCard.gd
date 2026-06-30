extends PanelContainer

# ─────────────────────────────────────────────────────────────────────────────
#  ParcelCard.gd
#  Composant UI pour une parcelle dans la phase d'enchères.
#
#  Structure de scène (ParcelCard.tscn) :
#  ParcelCard (PanelContainer, taille minimale : 120x140)
#  └── VBoxContainer
#      ├── TypeBadge (Label)       — icône du type spécial
#      ├── DepthRow (HBoxContainer)
#      │   ├── DepthIcon (Label)   — 🟢🟡🔴
#      │   └── DepthLabel (Label)
#      ├── SoilLabel (Label)
#      ├── ResourceIcon (Label)    — emoji ressource
#      ├── PriceLabel (Label)
#      ├── BidLabel (Label)        — mise du joueur
#      └── ResultOverlay (ColorRect, anchors=full, mouse_filter=IGNORE)
# ─────────────────────────────────────────────────────────────────────────────

signal parcel_selected(parcel: ParcelData)

var parcel_data: ParcelData = null
var _interactable: bool = true
var _bg_color: Color = Color.GRAY

@onready var type_badge:     Label     = $VBoxContainer/TypeBadge
@onready var depth_icon:     Label     = $VBoxContainer/DepthRow/DepthIcon
@onready var depth_label:    Label     = $VBoxContainer/DepthRow/DepthLabel
@onready var soil_label:     Label     = $VBoxContainer/SoilLabel
@onready var resource_icon:  Label     = $VBoxContainer/ResourceIcon
@onready var price_label:    Label     = $VBoxContainer/PriceLabel
@onready var bid_label:      Label     = $VBoxContainer/BidLabel
@onready var result_overlay: ColorRect = $ResultOverlay

# ─── Palettes ──────────────────────────────────────────────────────────────

const SOIL_BG_COLORS: Dictionary = {
	ParcelData.SoilType.CLAY:      Color(0.55, 0.38, 0.20, 1.0),
	ParcelData.SoilType.LIMESTONE: Color(0.62, 0.62, 0.55, 1.0),
	ParcelData.SoilType.GRANITE:   Color(0.35, 0.35, 0.42, 1.0),
	ParcelData.SoilType.VOLCANIC:  Color(0.28, 0.10, 0.10, 1.0),
}

const RESOURCE_ICONS: Dictionary = {
	ParcelData.ResourceHint.COAL:    "🪨",
	ParcelData.ResourceHint.IRON:    "⚙",
	ParcelData.ResourceHint.GOLD:    "✨",
	ParcelData.ResourceHint.GEM:     "💎",
	ParcelData.ResourceHint.CRYSTAL: "🔮",
	ParcelData.ResourceHint.NONE:    "💨",
	ParcelData.ResourceHint.UNKNOWN: "❓",
}

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	if result_overlay:
		result_overlay.hide()
	if bid_label:
		bid_label.text = ""

func setup(parcel: ParcelData) -> void:
	parcel_data = parcel
	_refresh()

func _refresh() -> void:
	if not parcel_data:
		return

	# Couleur de fond selon le sol
	var bg_color: Color = SOIL_BG_COLORS.get(parcel_data.soil_type, Color.GRAY)
	# Légère variation aléatoire pour un aspect moins uniforme
	bg_color = bg_color.lightened(randf_range(-0.05, 0.05))
	_bg_color = bg_color
	add_theme_stylebox_override("panel", _make_stylebox(bg_color))

	# Badge de type spécial
	var icon := parcel_data.get_type_icon()
	type_badge.text    = icon
	type_badge.visible = icon != ""

	# Profondeur
	depth_icon.text  = parcel_data.get_depth_icon()
	depth_label.text = parcel_data.get_depth_display()

	# Sol
	soil_label.text = parcel_data.get_soil_display()

	# Ressource
	resource_icon.text = RESOURCE_ICONS.get(parcel_data.resource_hint, "?")

	# Prix
	if parcel_data.base_price == 0:
		price_label.text     = "GRATUIT"
		price_label.modulate = Color.GREEN
	else:
		price_label.text     = "%d$" % parcel_data.base_price
		price_label.modulate = Color.WHITE

	# Parcelle réservée sans recherche → grisée
	if parcel_data.parcel_type == ParcelData.ParcelType.RESERVED:
		if not GameManager.player_corporation.has_research(parcel_data.required_research):
			modulate     = Color(0.45, 0.45, 0.45, 1.0)
			_interactable = false
			return

	modulate      = Color.WHITE
	_interactable = true

# ─── Mise du joueur ────────────────────────────────────────────────────────

func update_bid_display(amount: int) -> void:
	if amount > 0:
		bid_label.text     = "Offre : %d$" % amount
		bid_label.modulate = Color.CYAN
	else:
		bid_label.text = ""

# ─── Résultat après révélation ────────────────────────────────────────────

func show_result(player_won: bool, winner_id: int) -> void:
	result_overlay.show()

	if player_won:
		result_overlay.color = Color(0.0, 0.85, 0.0, 0.30)
		bid_label.text       = "✓ REMPORTÉE"
		bid_label.modulate   = Color.GREEN
	elif winner_id == -1:
		result_overlay.color = Color(0.5, 0.5, 0.5, 0.25)
		bid_label.text       = "Non réclamée"
		bid_label.modulate   = Color.GRAY
	else:
		result_overlay.color = Color(0.9, 0.1, 0.1, 0.30)
		var winner_corp: CorporationData = GameManager.get_corp_by_id(winner_id)
		var winner_name: String          = winner_corp.corp_name if winner_corp else "Inconnue"
		bid_label.text       = "❌ → %s" % winner_name
		bid_label.modulate   = Color.RED

# ─── Interaction souris ────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if not _interactable or not parcel_data:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			parcel_selected.emit(parcel_data)

func _on_mouse_entered() -> void:
	if _interactable:
		modulate = Color(1.15, 1.15, 1.15, 1.0)

func _on_mouse_exited() -> void:
	if _interactable:
		modulate = Color.WHITE

# ─── État d'enchère en temps réel ──────────────────────────────────────────

func set_auction_state(current_bid: int, holder_id: int, holder_color: Color, is_my_target: bool) -> void:
	if parcel_data and parcel_data.is_public:
		bid_label.text     = "Repli — %d$" % parcel_data.base_price
		bid_label.modulate = Color(0.7, 0.9, 0.7)
		_apply_border(Color(0.4, 0.5, 0.4), 2)
		return

	var border: Color
	if holder_id == -1:
		bid_label.text     = "Libre — %d$" % current_bid
		bid_label.modulate = Color(0.82, 0.82, 0.82)
		border = Color(0.4, 0.4, 0.4)
	elif holder_id == 0:
		bid_label.text     = "TOI — %d$" % current_bid
		bid_label.modulate = Color.CYAN
		border = Color.CYAN
	else:
		bid_label.text     = "%d$" % current_bid
		bid_label.modulate = holder_color
		border = holder_color

	_apply_border(border, 4 if is_my_target else 2)

func _apply_border(border_col: Color, border_w: int) -> void:
	add_theme_stylebox_override("panel", _make_stylebox_full(_bg_color, border_col, border_w))

# ─── Helper StyleBox ───────────────────────────────────────────────────────

func _make_stylebox(color: Color) -> StyleBoxFlat:
	return _make_stylebox_full(color, color.lightened(0.25), 2)

func _make_stylebox_full(bg: Color, border_col: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color             = bg
	sb.corner_radius_top_left     = 6
	sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_left  = 6
	sb.corner_radius_bottom_right = 6
	sb.border_width_left   = border_w
	sb.border_width_right  = border_w
	sb.border_width_top    = border_w
	sb.border_width_bottom = border_w
	sb.border_color        = border_col
	sb.content_margin_left   = 8.0
	sb.content_margin_right  = 8.0
	sb.content_margin_top    = 8.0
	sb.content_margin_bottom = 8.0
	return sb

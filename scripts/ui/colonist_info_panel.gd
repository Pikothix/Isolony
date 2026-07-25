extends PanelContainer
class_name ColonistInfoPanel

## Purpose: Present structured, readable identity and simulation information for the selected colonist.
## Responsibility: Project live Colonist read APIs into transient sections without owning or mutating colonist state.
## Assumption: Selection lifetime is coordinated by Main; this panel never stores simulation state.

@onready var _name_label: Label = $MarginContainer/VBoxContainer/IdentityPanel/IdentityMargin/IdentityVBox/NameLabel
@onready var _identity_meta_label: Label = $MarginContainer/VBoxContainer/IdentityPanel/IdentityMargin/IdentityVBox/IdentityMetaLabel
@onready var _activity_label: Label = $MarginContainer/VBoxContainer/IdentityPanel/IdentityMargin/IdentityVBox/ActivityLabel
@onready var _rest_value: Label = $MarginContainer/VBoxContainer/ContentScroll/Sections/NeedsGrid/RestValue
@onready var _warmth_value: Label = $MarginContainer/VBoxContainer/ContentScroll/Sections/NeedsGrid/WarmthValue
@onready var _shelter_value: Label = $MarginContainer/VBoxContainer/ContentScroll/Sections/NeedsGrid/ShelterValue
@onready var _hunger_value: Label = $MarginContainer/VBoxContainer/ContentScroll/Sections/NeedsGrid/HungerValue
@onready var _traits_label: Label = $MarginContainer/VBoxContainer/ContentScroll/Sections/TraitsLabel
@onready var _relationships_label: Label = $MarginContainer/VBoxContainer/ContentScroll/Sections/RelationshipsLabel
@onready var _skills_label: Label = $MarginContainer/VBoxContainer/ContentScroll/Sections/SkillsLabel
@onready var _work_priorities_label: Label = $MarginContainer/VBoxContainer/ContentScroll/Sections/WorkPrioritiesLabel

@export_range(0.05, 2.0, 0.05) var refresh_interval_seconds: float = 0.25

var _selected_colonist: Colonist
var _last_display_text: String = ""
var _refresh_elapsed := 0.0

func _ready() -> void:
	_reorganize_as_bottom_panel()
	clear_selection()

func _reorganize_as_bottom_panel() -> void:
	## The scene retains the source controls; this presentation-only pass groups them horizontally at runtime.
	var root: VBoxContainer = $MarginContainer/VBoxContainer
	var identity_panel: PanelContainer = root.get_node("IdentityPanel") as PanelContainer
	var content_scroll: ScrollContainer = root.get_node("ContentScroll") as ScrollContainer
	var sections: VBoxContainer = content_scroll.get_node("Sections") as VBoxContainer
	var horizontal_sections := HBoxContainer.new()
	horizontal_sections.name = "HorizontalSections"
	horizontal_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_sections.add_theme_constant_override("separation", 8)
	root.remove_child(identity_panel)
	root.remove_child(content_scroll)
	root.add_child(horizontal_sections)
	identity_panel.custom_minimum_size = Vector2(210.0, 0.0)
	identity_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	horizontal_sections.add_child(identity_panel)
	var needs_panel := _create_section("Needs", 210.0)
	var social_panel := _create_section("Relationships & Traits", 210.0)
	var skills_panel := _create_section("Skills", 190.0)
	var work_panel := _create_section("Work Priorities", 210.0)
	horizontal_sections.add_child(needs_panel)
	horizontal_sections.add_child(social_panel)
	horizontal_sections.add_child(skills_panel)
	horizontal_sections.add_child(work_panel)
	var needs_section := _get_section_content(needs_panel)
	var social_section := _get_section_content(social_panel)
	var skills_section := _get_section_content(skills_panel)
	var work_section := _get_section_content(work_panel)
	_move_to_section(sections.get_node("NeedsHeader"), needs_section)
	var needs_grid: GridContainer = sections.get_node("NeedsGrid") as GridContainer
	needs_grid.columns = 4
	_move_to_section(needs_grid, needs_section)
	_move_to_section(sections.get_node("RelationshipsHeader"), social_section)
	_move_to_section(sections.get_node("RelationshipsLabel"), social_section)
	_move_to_section(sections.get_node("TraitsHeader"), social_section)
	_move_to_section(sections.get_node("TraitsLabel"), social_section)
	_move_to_section(sections.get_node("SkillsHeader"), skills_section)
	_move_to_section(sections.get_node("SkillsLabel"), skills_section)
	_move_to_section(sections.get_node("WorkHeader"), work_section)
	_move_to_section(sections.get_node("WorkHint"), work_section)
	_move_to_section(sections.get_node("WorkPrioritiesLabel"), work_section)
	content_scroll.queue_free()

func _create_section(title: String, minimum_width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minimum_width, 0.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)
	margin.add_child(section)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	section.add_child(title_label)
	return panel

func _get_section_content(panel: PanelContainer) -> VBoxContainer:
	return panel.get_child(0).get_child(0) as VBoxContainer

func _move_to_section(control: Control, section: VBoxContainer) -> void:
	control.reparent(section)

func _process(delta: float) -> void:
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		clear_selection()
		return
	if not visible:
		return
	_refresh_elapsed -= maxf(delta, 0.0)
	if _refresh_elapsed > 0.0:
		return
	_refresh_elapsed = refresh_interval_seconds
	_refresh_display()

func display_colonist(colonist: Colonist) -> void:
	if colonist == null or not is_instance_valid(colonist):
		clear_selection()
		return
	_selected_colonist = colonist
	_last_display_text = ""
	_refresh_elapsed = refresh_interval_seconds
	_refresh_display()

func clear_selection() -> void:
	_selected_colonist = null
	_last_display_text = ""
	_refresh_elapsed = 0.0
	visible = false
	_clear_labels()

func get_display_snapshot() -> Dictionary:
	## Focused read-only validation hook for the current panel projection.
	return {
		"visible": visible,
		"name": _name_label.text if _name_label != null else "",
		"identity_meta": _identity_meta_label.text if _identity_meta_label != null else "",
		"nickname": _identity_meta_label.text if _identity_meta_label != null else "",
		"activity": _activity_label.text if _activity_label != null else "",
		"needs": _build_needs_snapshot(),
		"relationships": _relationships_label.text if _relationships_label != null else "",
		"traits": _traits_label.text if _traits_label != null else "",
		"work_priorities": _work_priorities_label.text if _work_priorities_label != null else "",
		"skills": _skills_label.text if _skills_label != null else "",
	}

func _refresh_display() -> void:
	var needs: Dictionary = _selected_colonist.get_needs_state()
	var identity_meta_text := "ID: %s" % _selected_colonist.colonist_id
	if not _selected_colonist.nickname.is_empty():
		identity_meta_text = "Nickname: %s\n%s" % [_selected_colonist.nickname, identity_meta_text]
	var activity_text := _selected_colonist.get_activity_name().capitalize()
	var rest_text := str(roundi(float(needs.get("rest", 0.0))))
	var warmth_text := str(roundi(float(needs.get("warmth", 0.0))))
	var shelter_text := str(roundi(float(needs.get("shelter", 0.0))))
	var hunger_text := str(roundi(float(needs.get("hunger", 0.0))))
	var relationships_text: String = _build_relationships_text()
	var trait_names: Array[String] = _selected_colonist.get_trait_display_names()
	var traits_text := "None" if trait_names.is_empty() else "\n".join(trait_names)
	var work_priorities_text: String = _build_work_priorities_text()
	var skills_text: String = _build_skills_text()
	var display_text := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [_selected_colonist.get_full_name(), identity_meta_text, activity_text, rest_text, warmth_text, shelter_text, hunger_text, relationships_text, traits_text, work_priorities_text, skills_text]
	if display_text == _last_display_text:
		return
	_last_display_text = display_text
	_name_label.text = _selected_colonist.get_full_name()
	_identity_meta_label.text = identity_meta_text
	_activity_label.text = "Activity: %s" % activity_text
	_rest_value.text = rest_text
	_warmth_value.text = warmth_text
	_shelter_value.text = shelter_text
	_hunger_value.text = hunger_text
	_relationships_label.text = relationships_text
	_traits_label.text = traits_text
	_work_priorities_label.text = work_priorities_text
	_skills_label.text = skills_text

func _build_work_priorities_text() -> String:
	var priorities: Dictionary = _selected_colonist.get_work_priorities()
	var lines: Array[String] = []
	for index: int in range(0, Colonist.WORK_TYPES.size(), 2):
		var left_type: String = Colonist.WORK_TYPES[index]
		var line := "%s %s" % [left_type, _format_priority(int(priorities.get(left_type, 0)))]
		if index + 1 < Colonist.WORK_TYPES.size():
			var right_type: String = Colonist.WORK_TYPES[index + 1]
			line += "    %s %s" % [right_type, _format_priority(int(priorities.get(right_type, 0)))]
		lines.append(line)
	return "\n".join(lines)

func _format_priority(value: int) -> String:
	return "-" if value == Colonist.WORK_DISABLED else str(value)

func _build_relationships_text() -> String:
	var relationships: Array[Dictionary] = _selected_colonist.get_relationships()
	var lines: Array[String] = []
	if relationships.is_empty():
		return "None"
	for relationship: Dictionary in relationships:
		var relation_type: String = String(relationship.get("relation_type", "unknown")).capitalize()
		var target_name: String = String(relationship.get("target_display_name", "Unknown"))
		lines.append("%s: %s" % [relation_type, target_name])
	return "\n".join(lines)

func _build_skills_text() -> String:
	var lines: Array[String] = []
	for skill_name: String in Colonist.SKILL_NAMES:
		var passion: String = _selected_colonist.get_skill_passion(skill_name)
		var marker := " ++" if passion == Colonist.PASSION_MAJOR else (" +" if passion == Colonist.PASSION_MINOR else "")
		lines.append("%s %d%s" % [skill_name, _selected_colonist.get_skill_level(skill_name), marker])
	return "\n".join(lines)

func _build_needs_snapshot() -> String:
	if _rest_value == null:
		return ""
	return "Rest: %s\nWarmth: %s\nShelter: %s\nHunger: %s" % [_rest_value.text, _warmth_value.text, _shelter_value.text, _hunger_value.text]

func _clear_labels() -> void:
	if _name_label == null:
		return
	_name_label.text = ""
	_identity_meta_label.text = ""
	_activity_label.text = ""
	_rest_value.text = "-"
	_warmth_value.text = "-"
	_shelter_value.text = "-"
	_hunger_value.text = "-"
	_traits_label.text = ""
	_relationships_label.text = ""
	_skills_label.text = ""
	_work_priorities_label.text = ""

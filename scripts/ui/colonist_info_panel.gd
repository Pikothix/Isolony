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

var _selected_colonist: Colonist
var _last_display_text: String = ""

func _ready() -> void:
	clear_selection()

func _process(_delta: float) -> void:
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		clear_selection()
		return
	_refresh_display()

func display_colonist(colonist: Colonist) -> void:
	if colonist == null or not is_instance_valid(colonist):
		clear_selection()
		return
	_selected_colonist = colonist
	_last_display_text = ""
	visible = true
	_refresh_display()

func clear_selection() -> void:
	_selected_colonist = null
	_last_display_text = ""
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

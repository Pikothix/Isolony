extends PanelContainer
class_name ColonistInfoPanel

## Purpose: Debug-level presentation and minimal work-priority controls for the selected colonist.
## Responsibility: Project colonist state and forward priority edit requests to the authoritative Colonist.
## Assumption: Selection lifetime is coordinated by Main; this panel never stores simulation state.

@onready var _name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var _nickname_label: Label = $MarginContainer/VBoxContainer/NicknameLabel
@onready var _activity_label: Label = $MarginContainer/VBoxContainer/ActivityLabel
@onready var _needs_label: Label = $MarginContainer/VBoxContainer/NeedsLabel
@onready var _relationships_label: Label = $MarginContainer/VBoxContainer/RelationshipsLabel
@onready var _traits_label: Label = $MarginContainer/VBoxContainer/TraitsLabel
@onready var _work_priorities_label: Label = $MarginContainer/VBoxContainer/WorkPrioritiesLabel
@onready var _construct_priority_button: Button = $MarginContainer/VBoxContainer/WorkPriorityButtons/ConstructPriorityButton
@onready var _harvest_priority_button: Button = $MarginContainer/VBoxContainer/WorkPriorityButtons/HarvestPriorityButton
@onready var _haul_priority_button: Button = $MarginContainer/VBoxContainer/WorkPriorityButtons/HaulPriorityButton
@onready var _skills_label: Label = $MarginContainer/VBoxContainer/SkillsLabel

var _selected_colonist: Colonist
var _last_display_text: String = ""

func _ready() -> void:
	visible = false
	_construct_priority_button.pressed.connect(_on_construct_priority_pressed)
	_harvest_priority_button.pressed.connect(_on_harvest_priority_pressed)
	_haul_priority_button.pressed.connect(_on_haul_priority_pressed)

func _process(_delta: float) -> void:
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		clear_selection()
		return
	_refresh_display()

func display_colonist(colonist: Colonist) -> void:
	_selected_colonist = colonist
	_last_display_text = ""
	visible = colonist != null and is_instance_valid(colonist)
	if visible:
		_refresh_display()

func clear_selection() -> void:
	_selected_colonist = null
	_last_display_text = ""
	visible = false

func get_display_snapshot() -> Dictionary:
	## Focused read-only validation hook for the current panel projection.
	return {
		"visible": visible,
		"name": _name_label.text if _name_label != null else "",
		"nickname": _nickname_label.text if _nickname_label != null else "",
		"activity": _activity_label.text if _activity_label != null else "",
		"needs": _needs_label.text if _needs_label != null else "",
		"relationships": _relationships_label.text if _relationships_label != null else "",
		"traits": _traits_label.text if _traits_label != null else "",
		"work_priorities": _work_priorities_label.text if _work_priorities_label != null else "",
		"skills": _skills_label.text if _skills_label != null else "",
	}

func _refresh_display() -> void:
	var nickname_text := "Nickname: %s" % _selected_colonist.nickname if not _selected_colonist.nickname.is_empty() else ""
	var activity_text := "Activity: %s" % _selected_colonist.get_activity_name().capitalize()
	var needs_text := "Rest: %d\nWarmth: %d\nShelter: %d\nHunger: %d" % [
		roundi(_selected_colonist.rest),
		roundi(_selected_colonist.warmth),
		roundi(_selected_colonist.shelter),
		roundi(_selected_colonist.hunger),
	]
	var relationships_text: String = _build_relationships_text()
	var traits_text := "Traits: %s" % ", ".join(_selected_colonist.get_trait_display_names())
	var work_priorities_text: String = _build_work_priorities_text()
	var skills_text: String = _build_skills_text()
	var display_text := "%s|%s|%s|%s|%s|%s|%s|%s" % [_selected_colonist.get_full_name(), nickname_text, activity_text, needs_text, relationships_text, traits_text, work_priorities_text, skills_text]
	if display_text == _last_display_text:
		return
	_last_display_text = display_text
	_name_label.text = _selected_colonist.get_full_name()
	_nickname_label.text = nickname_text
	_nickname_label.visible = not nickname_text.is_empty()
	_activity_label.text = activity_text
	_needs_label.text = needs_text
	_relationships_label.text = relationships_text
	_traits_label.text = traits_text
	_work_priorities_label.text = work_priorities_text
	_construct_priority_button.text = "Construct: %s" % _format_priority(_selected_colonist.get_work_priority("Construct"))
	_harvest_priority_button.text = "Harvest: %s" % _format_priority(_selected_colonist.get_work_priority("Harvest"))
	_haul_priority_button.text = "Haul: %s" % _format_priority(_selected_colonist.get_work_priority("Haul"))
	_skills_label.text = skills_text

func _build_work_priorities_text() -> String:
	var priorities: Dictionary = _selected_colonist.get_work_priorities()
	var lines: Array[String] = ["Work Priorities (1 highest, - disabled):"]
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

func _on_construct_priority_pressed() -> void:
	_cycle_work_priority("Construct")

func _on_harvest_priority_pressed() -> void:
	_cycle_work_priority("Harvest")

func _on_haul_priority_pressed() -> void:
	_cycle_work_priority("Haul")

func _cycle_work_priority(work_type: String) -> void:
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		return
	var current: int = _selected_colonist.get_work_priority(work_type)
	_selected_colonist.set_work_priority(work_type, (current + 1) % (Colonist.WORK_PRIORITY_MAX + 1))
	_last_display_text = ""
	_refresh_display()

func _build_relationships_text() -> String:
	var relationships: Array[Dictionary] = _selected_colonist.get_relationships()
	var lines: Array[String] = ["Relationships:"]
	if relationships.is_empty():
		lines.append("None")
		return "\n".join(lines)
	for relationship: Dictionary in relationships:
		var relation_type: String = String(relationship.get("relation_type", "unknown")).capitalize()
		var target_name: String = String(relationship.get("target_display_name", "Unknown"))
		lines.append("%s: %s" % [relation_type, target_name])
	return "\n".join(lines)

func _build_skills_text() -> String:
	var lines: Array[String] = ["Skills:"]
	for skill_name: String in Colonist.SKILL_NAMES:
		var passion: String = _selected_colonist.get_skill_passion(skill_name)
		var marker := " ++" if passion == Colonist.PASSION_MAJOR else (" +" if passion == Colonist.PASSION_MINOR else "")
		lines.append("%s %d%s" % [skill_name, _selected_colonist.get_skill_level(skill_name), marker])
	return "\n".join(lines)

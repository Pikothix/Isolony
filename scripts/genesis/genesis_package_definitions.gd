extends RefCounted

## Immutable Genesis package catalogue. Unlock data is interpreted by the
## simulation so terminal presentation remains independent of package rules.

const DEFINITIONS: Array[Dictionary] = [
	{
		"id": &"STATUS",
		"display_name": "STATUS",
		"cost": 5,
		"unlock_command": &"status",
		"unlock_ui_feature": &"",
	},
	{
		"id": &"RESOURCE_MONITOR",
		"display_name": "RESOURCE_MONITOR",
		"cost": 15,
		"unlock_command": &"",
		"unlock_ui_feature": &"resource_monitor",
	},
	{
		"id": &"LOGGER",
		"display_name": "LOGGER",
		"cost": 20,
		"unlock_command": &"",
		"unlock_ui_feature": &"kernel_log",
	},
	{
		"id": &"COMMAND_HISTORY",
		"display_name": "COMMAND_HISTORY",
		"cost": 30,
		"unlock_command": &"",
		"unlock_ui_feature": &"command_history",
	},
	{
		"id": &"ANSI",
		"display_name": "ANSI",
		"cost": 50,
		"unlock_command": &"",
		"unlock_ui_feature": &"ansi",
	},
]


static func get_all() -> Array[Dictionary]:
	return DEFINITIONS


static func get_definition(package_id: StringName) -> Dictionary:
	for definition: Dictionary in DEFINITIONS:
		if definition.id == package_id:
			return definition
	return {}

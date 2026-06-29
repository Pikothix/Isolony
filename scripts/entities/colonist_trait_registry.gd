extends RefCounted

## Purpose: Central data registry for the small Milestone 25 colonist trait set.
## Responsibility: Define display metadata, exclusions, and bounded gameplay modifiers.
## Assumption: Saves store trait ids; display metadata and modifiers are re-derived from this registry.

const TRAIT_IDS: Array[String] = [
	"hard_worker",
	"lazy",
	"night_owl",
	"brave",
	"coward",
	"fast_learner",
	"kind",
	"greedy",
]

const TRAITS: Dictionary = {
	"hard_worker": {
		"display_name": "Hard Worker",
		"description": "Works steadily and builds faster.",
		"modifiers": {"construction_work_rate_multiplier": 1.25},
		"excludes": ["lazy"],
	},
	"lazy": {
		"display_name": "Lazy",
		"description": "Takes a slower approach to construction.",
		"modifiers": {"construction_work_rate_multiplier": 0.75},
		"excludes": ["hard_worker"],
	},
	"night_owl": {
		"display_name": "Night Owl",
		"description": "Loses Rest more slowly at night.",
		"modifiers": {"night_rest_decay_multiplier": 0.5},
		"excludes": [],
	},
	"brave": {
		"display_name": "Brave",
		"description": "Keeps their nerve under pressure.",
		"modifiers": {},
		"excludes": ["coward"],
	},
	"coward": {
		"display_name": "Coward",
		"description": "Prefers to avoid danger.",
		"modifiers": {},
		"excludes": ["brave"],
	},
	"fast_learner": {
		"display_name": "Fast Learner",
		"description": "Learns quickly once skill XP exists.",
		"modifiers": {},
		"excludes": [],
	},
	"kind": {
		"display_name": "Kind",
		"description": "Inclined to treat others well.",
		"modifiers": {},
		"excludes": [],
	},
	"greedy": {
		"display_name": "Greedy",
		"description": "Values personal wealth highly.",
		"modifiers": {},
		"excludes": [],
	},
}

static func has_trait(trait_id: String) -> bool:
	return TRAITS.has(trait_id)

static func get_trait(trait_id: String) -> Dictionary:
	if not TRAITS.has(trait_id):
		return {}
	var definition: Dictionary = TRAITS[trait_id]
	var result: Dictionary = definition.duplicate(true)
	result["id"] = trait_id
	return result

static func are_conflicting(first_trait_id: String, second_trait_id: String) -> bool:
	if not TRAITS.has(first_trait_id) or not TRAITS.has(second_trait_id):
		return false
	var first: Dictionary = TRAITS[first_trait_id]
	var second: Dictionary = TRAITS[second_trait_id]
	return second_trait_id in first.get("excludes", []) or first_trait_id in second.get("excludes", [])

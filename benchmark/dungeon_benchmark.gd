extends Node

## Standalone benchmark for the dungeon generator. Run this scene directly
## (F6 in the Godot editor) - it never touches gameplay, never instances a
## room scene, and never adds anything to the running game.
##
## It measures DungeonGenerator alone: how long a layout takes to produce,
## and whether the layout satisfies the invariants the generator promises
## (no two rooms share a cell, every room is reachable from the start room,
## exactly one boss room and one item room, both of them dead ends).
##
## Output goes to the Output panel: a human-readable summary followed by a
## CSV block that can be pasted straight into the report's charts.

## Layout sizes to measure. The shipped game uses target_room_count = 6 on
## floor 1 and +3 per floor (see dungeon_root.gd), so 6/9/12 covers exactly
## the three floors a real run goes through.
const ROOM_COUNTS: Array[int] = [6, 9, 12]

## Runs per size. 1000 is enough for the failure-rate percentages below to
## be meaningful to a tenth of a percent.
const RUNS_PER_COUNT: int = 1000

var _start_templates: Array[RoomTemplate] = []
var _normal_templates: Array[RoomTemplate] = []
var _empty_template: RoomTemplate


func _ready() -> void:
	if not _load_templates_from_game_scene():
		return

	print("=".repeat(72))
	print("INSECTARIUM - DUNGEON GENERATOR BENCHMARK")
	print("=".repeat(72))
	print("Godot: %s" % Engine.get_version_info().string)
	print("Templates: %d start, %d normal, empty=%s" % [
		_start_templates.size(),
		_normal_templates.size(),
		"yes" if _empty_template != null else "NO (boss/item rooms will be missing)",
	])
	print("Runs per configuration: %d" % RUNS_PER_COUNT)
	print("")

	var all_results: Array[Dictionary] = []
	for count in ROOM_COUNTS:
		var result := _benchmark_one_configuration(count)
		all_results.append(result)
		_print_report(result)

	_print_csv(all_results)

	print("")
	print("Benchmark finished. Copy everything above into the report.")
	get_tree().quit()


## Reads the exact template arrays the shipped game uses, by instantiating
## dungeon.tscn WITHOUT adding it to the tree - exported properties are
## populated by instantiate(), while _ready() only runs on tree entry, so
## no dungeon is actually built. Keeps the benchmark honest: it measures the
## same 27 templates the player plays with, not a hand-copied subset.
func _load_templates_from_game_scene() -> bool:
	var scene: PackedScene = load("res://dungeon.tscn")
	if scene == null:
		push_error("Benchmark: could not load res://dungeon.tscn")
		return false

	var root: Node = scene.instantiate()
	if root == null:
		push_error("Benchmark: could not instantiate dungeon.tscn")
		return false

	_start_templates.assign(root.start_templates)
	_normal_templates.assign(root.normal_templates)
	_empty_template = root.empty_room_template

	root.free()

	if _start_templates.is_empty() or _normal_templates.is_empty():
		push_error("Benchmark: dungeon.tscn has no templates assigned")
		return false
	return true


func _benchmark_one_configuration(target_count: int) -> Dictionary:
	var times_ms: Array[float] = []
	var room_counts: Array[int] = []
	var boss_distances: Array[int] = []

	var connected_ok: int = 0
	var no_overlap_ok: int = 0
	var reciprocal_ok: int = 0
	var has_boss: int = 0
	var has_item: int = 0
	var boss_is_dead_end: int = 0
	var reached_target: int = 0

	for i in RUNS_PER_COUNT:
		var generator := DungeonGenerator.new()
		generator.start_templates = _start_templates
		generator.normal_templates = _normal_templates
		generator.empty_room_template = _empty_template
		generator.target_room_count = target_count

		var t0 := Time.get_ticks_usec()
		var layout: Array[PlacedRoom] = generator.generate()
		var t1 := Time.get_ticks_usec()

		times_ms.append(float(t1 - t0) / 1000.0)
		room_counts.append(layout.size())
		if layout.size() >= target_count:
			reached_target += 1

		var check := _validate_layout(layout)
		if check["connected"]:
			connected_ok += 1
		if check["no_overlap"]:
			no_overlap_ok += 1
		if check["reciprocal"]:
			reciprocal_ok += 1
		if check["boss_id"] != -1:
			has_boss += 1
			boss_distances.append(check["boss_distance"])
			if check["boss_degree"] == 1:
				boss_is_dead_end += 1
		if check["item_id"] != -1:
			has_item += 1

	return {
		"target_count": target_count,
		"runs": RUNS_PER_COUNT,
		"time_mean": _mean(times_ms),
		"time_min": times_ms.min(),
		"time_max": times_ms.max(),
		"time_stddev": _stddev(times_ms),
		"rooms_mean": _mean_int(room_counts),
		"rooms_min": room_counts.min(),
		"rooms_max": room_counts.max(),
		"reached_target": reached_target,
		"connected_ok": connected_ok,
		"no_overlap_ok": no_overlap_ok,
		"reciprocal_ok": reciprocal_ok,
		"has_boss": has_boss,
		"has_item": has_item,
		"boss_is_dead_end": boss_is_dead_end,
		"boss_distance_mean": _mean_int(boss_distances),
		"boss_distance_histogram": _histogram(boss_distances),
	}


## Checks every invariant dungeon_generator.gd is supposed to guarantee.
## Returns a dictionary of independent pass/fail flags plus the facts the
## report needs about the boss room, so one generate() call produces every
## measurement at once.
func _validate_layout(layout: Array[PlacedRoom]) -> Dictionary:
	var result := {
		"connected": false,
		"no_overlap": true,
		"reciprocal": true,
		"boss_id": -1,
		"item_id": -1,
		"boss_distance": -1,
		"boss_degree": -1,
	}
	if layout.is_empty():
		return result

	var by_id := {}
	for room in layout:
		by_id[room.id] = room

	# --- Invariant 1: no grid cell is claimed by two rooms ---
	var cell_owner := {}
	for room in layout:
		for cell in room.occupied_cells:
			if cell_owner.has(cell):
				result["no_overlap"] = false
			cell_owner[cell] = room.id

	# --- Invariant 2: every connection is mutual (A->B implies B->A) ---
	for room in layout:
		for slot in room.world_door_slots:
			var other_id: int = slot["connected_to"]
			if other_id == -1:
				continue
			if not by_id.has(other_id):
				result["reciprocal"] = false
				continue
			var found := false
			for other_slot in (by_id[other_id] as PlacedRoom).world_door_slots:
				if other_slot["connected_to"] == room.id:
					found = true
					break
			if not found:
				result["reciprocal"] = false

	# --- Invariant 3: every room is reachable from the start room (id 0) ---
	var distances := _bfs_distances(by_id, 0)
	result["connected"] = distances.size() == layout.size()

	# --- Special rooms ---
	for room in layout:
		if room.room_type == RoomTemplate.RoomType.BOSS and result["boss_id"] == -1:
			result["boss_id"] = room.id
			result["boss_distance"] = distances.get(room.id, -1)
			result["boss_degree"] = _degree(room)
		elif room.room_type == RoomTemplate.RoomType.ITEM and result["item_id"] == -1:
			result["item_id"] = room.id

	return result


## Same BFS dungeon_generator.gd uses to pick the boss room, re-implemented
## here so the benchmark verifies the result independently instead of
## trusting the generator's own bookkeeping.
func _bfs_distances(by_id: Dictionary, start_id: int) -> Dictionary:
	if not by_id.has(start_id):
		return {}
	var distances := {start_id: 0}
	var queue: Array[int] = [start_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for slot in (by_id[current] as PlacedRoom).world_door_slots:
			var other_id: int = slot["connected_to"]
			if other_id != -1 and by_id.has(other_id) and not distances.has(other_id):
				distances[other_id] = distances[current] + 1
				queue.append(other_id)
	return distances


## Number of rooms this room is connected to. A genuine dead end has 1.
func _degree(room: PlacedRoom) -> int:
	var count := 0
	for slot in room.world_door_slots:
		if slot["connected_to"] != -1:
			count += 1
	return count


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


func _mean_int(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for v in values:
		total += v
	return float(total) / float(values.size())


func _stddev(values: Array[float]) -> float:
	if values.size() < 2:
		return 0.0
	var m := _mean(values)
	var sum_sq := 0.0
	for v in values:
		sum_sq += (v - m) * (v - m)
	return sqrt(sum_sq / float(values.size() - 1))


## distance -> how many runs had the boss room at that BFS distance.
func _histogram(values: Array[int]) -> Dictionary:
	var histogram := {}
	for v in values:
		histogram[v] = histogram.get(v, 0) + 1
	return histogram


func _percent(part: int, whole: int) -> String:
	if whole == 0:
		return "n/a"
	return "%.1f%% (%d/%d)" % [100.0 * float(part) / float(whole), part, whole]


func _print_report(r: Dictionary) -> void:
	var runs: int = r["runs"]
	print("-".repeat(72))
	print("target_room_count = %d   (%d runs)" % [r["target_count"], runs])
	print("-".repeat(72))
	print("  Generation time (ms)")
	print("    mean   : %.4f" % r["time_mean"])
	print("    min    : %.4f" % r["time_min"])
	print("    max    : %.4f" % r["time_max"])
	print("    stddev : %.4f" % r["time_stddev"])
	print("  Layout size")
	print("    rooms mean/min/max : %.2f / %d / %d" % [r["rooms_mean"], r["rooms_min"], r["rooms_max"]])
	print("    reached target     : %s" % _percent(r["reached_target"], runs))
	print("  Invariants")
	print("    fully connected    : %s" % _percent(r["connected_ok"], runs))
	print("    no cell overlap    : %s" % _percent(r["no_overlap_ok"], runs))
	print("    doors reciprocal   : %s" % _percent(r["reciprocal_ok"], runs))
	print("  Special rooms")
	print("    boss room placed   : %s" % _percent(r["has_boss"], runs))
	print("    item room placed   : %s" % _percent(r["has_item"], runs))
	print("    boss is a dead end : %s" % _percent(r["boss_is_dead_end"], r["has_boss"]))
	print("    boss BFS distance  : mean %.2f" % r["boss_distance_mean"])
	var histogram: Dictionary = r["boss_distance_histogram"]
	var keys: Array = histogram.keys()
	keys.sort()
	for k in keys:
		print("      distance %2d : %4d run(s)" % [k, histogram[k]])
	print("")


## CSV for the report's charts. Printed as one block so it can be selected
## and pasted into pgfplots / a spreadsheet without hand-editing.
func _print_csv(results: Array[Dictionary]) -> void:
	print("=".repeat(72))
	print("CSV - summary per configuration")
	print("=".repeat(72))
	print("target_rooms,runs,time_mean_ms,time_min_ms,time_max_ms,time_stddev_ms,rooms_mean,connected_pct,no_overlap_pct,boss_placed_pct,item_placed_pct,boss_dead_end_pct,boss_distance_mean")
	for r in results:
		var runs: int = r["runs"]
		var boss: int = r["has_boss"]
		print("%d,%d,%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [
			r["target_count"], runs,
			r["time_mean"], r["time_min"], r["time_max"], r["time_stddev"],
			r["rooms_mean"],
			100.0 * float(r["connected_ok"]) / float(runs),
			100.0 * float(r["no_overlap_ok"]) / float(runs),
			100.0 * float(boss) / float(runs),
			100.0 * float(r["has_item"]) / float(runs),
			(100.0 * float(r["boss_is_dead_end"]) / float(boss)) if boss > 0 else 0.0,
			r["boss_distance_mean"],
		])

	print("")
	print("CSV - boss room BFS distance distribution")
	print("target_rooms,bfs_distance,run_count")
	for r in results:
		var histogram: Dictionary = r["boss_distance_histogram"]
		var keys: Array = histogram.keys()
		keys.sort()
		for k in keys:
			print("%d,%d,%d" % [r["target_count"], k, histogram[k]])

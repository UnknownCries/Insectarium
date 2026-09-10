class_name DungeonGenerator
extends RefCounted

## Generates a dungeon layout as a list of PlacedRoom objects. Does NOT
## instance any scenes - that's dungeon_builder.gd's job.

var grid: Dictionary = {}         # Vector2i -> room id (int), sparse
var rooms: Dictionary = {}        # room id (int) -> PlacedRoom
var frontier: Array[Dictionary] = []  # {"room_id": int, "slot": Dictionary}
var _next_id: int = 0

var target_room_count: int = 10
var max_placement_attempts_per_step: int = 20  # retry cap to avoid infinite loops
var verbose_trace: bool = false  # set true to re-enable per-step PLACE: prints (noisy, can scroll off for large room counts)

var start_templates: Array[RoomTemplate] = []
var normal_templates: Array[RoomTemplate] = []

# The dedicated empty-1x1 template placed as the two guaranteed dead ends
# (boss room + item room) after normal growth - see _place_guaranteed_dead_end().
var empty_room_template: RoomTemplate


func generate() -> Array[PlacedRoom]:
	grid.clear()
	rooms.clear()
	frontier.clear()
	_next_id = 0

	# Validate all templates up front to catch authoring mistakes early.
	for t in normal_templates:
		_validate_template(t)
	if empty_room_template != null:
		_validate_template(empty_room_template)

	_place_start_room()

	var safety_counter := 0
	var max_safety := target_room_count * max_placement_attempts_per_step * 4

	while rooms.size() < target_room_count and frontier.size() > 0:
		safety_counter += 1
		if safety_counter > max_safety:
			push_warning("DungeonGenerator: hit safety limit, stopping early with %d rooms" % rooms.size())
			break

		if not _try_place_one_room():
			# Could not grow at all this pass; nothing more to do.
			break

	# Place exactly two guaranteed empty 1x1 dead ends - one becomes the
	# boss room, one the item room (decided by BFS distance below).
	var dead_end_ids: Array[int] = []
	if empty_room_template != null:
		for i in 2:
			var new_id := _place_guaranteed_dead_end(empty_room_template)
			if new_id != -1:
				dead_end_ids.append(new_id)
	else:
		push_warning("DungeonGenerator: empty_room_template not set - no boss/item room will be placed")

	_assign_special_rooms(dead_end_ids)

	if verbose_trace:
		_print_debug_report()

	var result: Array[PlacedRoom] = []
	for r in rooms.values():
		result.append(r)
	return result


func _print_debug_report() -> void:
	print("=== DUNGEON DEBUG REPORT (%d rooms) ===" % rooms.size())

	# Check for any cell claimed by more than one room (should be impossible
	# given _can_place, but verify directly from final state).
	var cell_owner := {}
	var overlap_found := false
	for room in rooms.values():
		for cell in room.occupied_cells:
			if cell_owner.has(cell):
				overlap_found = true
				print("  OVERLAP: cell %s claimed by both room %d and room %d" % [cell, cell_owner[cell], room.id])
			cell_owner[cell] = room.id
	if not overlap_found:
		print("  No cell overlaps found.")

	# Check every door slot: report any that are OPEN (unconnected) so you
	# can see exactly which walls will show as gaps with nothing behind them,
	# vs which are genuinely sealed (BUILD WALL, no gap, no bug).
	var open_count := 0
	for room in rooms.values():
		for slot in room.world_door_slots:
			if slot["connected_to"] == -1:
				open_count += 1
				print("  OPEN DOOR (no bug - just unused): room %d cell=%s dir=%d" % [room.id, slot["cell"], slot["direction"]])
	print("  %d open/unconnected door slots (these get walls, not gaps - not a bug)" % open_count)

	# Check every CONNECTED door slot has a reciprocal connection on the
	# other room (A says connected_to=B, B should say connected_to=A).
	var mismatch_found := false
	for room in rooms.values():
		for slot in room.world_door_slots:
			var other_id: int = slot["connected_to"]
			if other_id == -1:
				continue
			if not rooms.has(other_id):
				mismatch_found = true
				print("  BROKEN LINK: room %d door at cell=%s dir=%d points to non-existent room %d" % [room.id, slot["cell"], slot["direction"], other_id])
				continue
			var other_room: PlacedRoom = rooms[other_id]
			var found_reciprocal := false
			for other_slot in other_room.world_door_slots:
				if other_slot["connected_to"] == room.id:
					found_reciprocal = true
					break
			if not found_reciprocal:
				mismatch_found = true
				print("  ONE-WAY LINK: room %d door at cell=%s dir=%d says connected_to=%d, but room %d has no door pointing back" % [
					room.id, slot["cell"], slot["direction"], other_id, other_id
				])
	if not mismatch_found:
		print("  All connections are properly reciprocal.")

	print("=== END DEBUG REPORT ===")


func _place_start_room() -> void:
	var template: RoomTemplate = start_templates.pick_random()
	_validate_template(template)
	var room := PlacedRoom.new(template, Vector2i.ZERO, _next_id)
	_next_id += 1
	_commit_room(room)


## Checks that every door slot's cell actually exists in the template's
## footprint - a door outside the footprint silently causes misaligned/
## overlapping placement.
func _validate_template(template: RoomTemplate) -> void:
	var footprint_set := {}
	for cell in template.footprint:
		footprint_set[cell] = true
	for slot in template.door_slots:
		if not footprint_set.has(slot.cell):
			push_error("TEMPLATE BUG: %s has a door slot at cell %s which is NOT part of its footprint %s" % [
				template.resource_path, slot.cell, template.footprint
			])


## Picks a random open door from the frontier, tries candidate templates
## until one fits, and commits it. Returns false if nothing in
## the frontier could be grown after exhausting attempts (dead end everywhere).
func _try_place_one_room() -> bool:
	# Shuffle a working copy so we don't always favor the same frontier order
	var frontier_indices := range(frontier.size())
	frontier_indices.shuffle()

	for f_idx in frontier_indices:
		var entry := frontier[f_idx]
		var source_room: PlacedRoom = rooms[entry["room_id"]]
		var source_slot: Dictionary = entry["slot"]

		if source_slot["connected_to"] != -1:
			continue  # already got connected from another attempt; skip

		var placed := _attempt_fill_slot(source_room, source_slot)
		if placed:
			# Remove this frontier entry now that it's connected
			frontier.remove_at(f_idx)
			return true

	# Nothing in the whole frontier could be grown this pass.
	# Prune any dead (already-connected) entries and report failure.
	_prune_frontier()
	return false


func _attempt_fill_slot(source_room: PlacedRoom, source_slot: Dictionary) -> bool:
	var needed_direction: DoorSlot.Direction = RoomTemplate.opposite_direction(source_slot["direction"])
	var target_cell: Vector2i = source_slot["cell"] + RoomTemplate.direction_to_vector(source_slot["direction"])

	var candidates := _weighted_shuffle(normal_templates)

	for template in candidates:
		for slot in template.door_slots:
			if slot.direction != needed_direction:
				continue
			# This door, if placed so that `slot.cell` lands on target_cell,
			# would connect back to source_room. Compute the room's origin.
			var candidate_origin: Vector2i = target_cell - slot.cell
			if _can_place(template, candidate_origin):
				if verbose_trace:
					var world_cells: Array[Vector2i] = []
					for lc in template.footprint:
						world_cells.append(lc + candidate_origin)
					print("PLACE: template=%s origin=%s world_cells=%s (from source room %d, slot dir=%d, target_cell=%s)" % [
						template.resource_path, candidate_origin, world_cells, source_room.id, source_slot["direction"], target_cell
					])

				var new_room := PlacedRoom.new(template, candidate_origin, _next_id)
				_next_id += 1
				_commit_room(new_room)
				source_room.connect_door(source_slot["cell"], source_slot["direction"], new_room.id)
				new_room.connect_door(target_cell, needed_direction, source_room.id)
				return true
	return false


## Forces `template` onto a random open frontier slot. Does NOT add the new
## room's other open door slots to the frontier, so it stays a genuine
## single-connection dead end. Returns the new room's id, or -1 if no open
## slot could fit it anywhere.
func _place_guaranteed_dead_end(template: RoomTemplate) -> int:
	var indices := range(frontier.size())
	indices.shuffle()

	for f_idx in indices:
		var entry := frontier[f_idx]
		var source_room: PlacedRoom = rooms[entry["room_id"]]
		var source_slot: Dictionary = entry["slot"]

		if source_slot["connected_to"] != -1:
			continue  # already got connected from another attempt; skip

		var needed_direction: DoorSlot.Direction = RoomTemplate.opposite_direction(source_slot["direction"])
		var target_cell: Vector2i = source_slot["cell"] + RoomTemplate.direction_to_vector(source_slot["direction"])

		for slot in template.door_slots:
			if slot.direction != needed_direction:
				continue
			var candidate_origin: Vector2i = target_cell - slot.cell
			if _can_place(template, candidate_origin):
				var new_room := PlacedRoom.new(template, candidate_origin, _next_id)
				_next_id += 1

				for cell in new_room.occupied_cells:
					grid[cell] = new_room.id
				rooms[new_room.id] = new_room
				# Not calling _commit_room() - it would add this room's open
				# door slots to the frontier, defeating the dead-end guarantee.

				source_room.connect_door(source_slot["cell"], source_slot["direction"], new_room.id)
				new_room.connect_door(target_cell, needed_direction, source_room.id)
				frontier.remove_at(f_idx)
				return new_room.id
	return -1


func _can_place(template: RoomTemplate, origin: Vector2i) -> bool:
	for local_cell in template.footprint:
		var world_cell := local_cell + origin
		if grid.has(world_cell):
			return false
	return true


func _commit_room(room: PlacedRoom) -> void:
	# Sanity check: verify no cell we're about to claim is already taken.
	# If this fires, _can_place let something through it shouldn't have.
	for cell in room.occupied_cells:
		if grid.has(cell):
			var existing_id: int = grid[cell]
			push_error("OVERLAP BUG: room %d (template=%s, origin=%s) wants cell %s, already owned by room %d" % [
				room.id, room.template.resource_path, room.origin, cell, existing_id
			])

	for cell in room.occupied_cells:
		grid[cell] = room.id
	rooms[room.id] = room
	for slot in room.get_open_door_slots():
		frontier.append({"room_id": room.id, "slot": slot})


func _prune_frontier() -> void:
	frontier = frontier.filter(func(e):
		var room: PlacedRoom = rooms[e["room_id"]]
		for s in room.world_door_slots:
			if s["cell"] == e["slot"]["cell"] and s["direction"] == e["slot"]["direction"]:
				return s["connected_to"] == -1
		return false
	)


func _weighted_shuffle(templates: Array[RoomTemplate]) -> Array[RoomTemplate]:
	# Weighted reservoir-style ordering: repeatedly pick one remaining
	# template with probability proportional to its weight, remove it, repeat.
	var remaining: Array[RoomTemplate] = templates.duplicate()
	var result: Array[RoomTemplate] = []

	while remaining.size() > 0:
		var total_weight := 0.0
		for t in remaining:
			total_weight += max(0.0001, t.weight)  # avoid zero/negative weights breaking selection

		var roll := randf() * total_weight
		var cumulative := 0.0
		var chosen_index := 0
		for i in remaining.size():
			cumulative += max(0.0001, remaining[i].weight)
			if roll <= cumulative:
				chosen_index = i
				break

		result.append(remaining[chosen_index])
		remaining.remove_at(chosen_index)

	return result


## Tags the two guaranteed empty-1x1 dead ends as BOSS and ITEM: whichever
## is farther from the start room by BFS distance becomes the boss room,
## the other the item room. dead_end_ids may have 0-2 entries if placement
## couldn't find a free slot for one/both - degrades gracefully.
func _assign_special_rooms(dead_end_ids: Array[int]) -> void:
	if rooms.is_empty() or dead_end_ids.is_empty():
		return

	var start_id := 0  # start room is always id 0 by construction
	var distances := _bfs_distances(start_id)

	var boss_id: int = dead_end_ids[0]
	var boss_dist: int = distances.get(boss_id, 0)
	for id in dead_end_ids:
		var d: int = distances.get(id, 0)
		if d > boss_dist:
			boss_dist = d
			boss_id = id
	rooms[boss_id].room_type = RoomTemplate.RoomType.BOSS

	for id in dead_end_ids:
		if id != boss_id:
			rooms[id].room_type = RoomTemplate.RoomType.ITEM
			break


func _bfs_distances(start_id: int) -> Dictionary:
	var distances := {start_id: 0}
	var queue := [start_id]
	while queue.size() > 0:
		var current_id: int = queue.pop_front()
		var current_room: PlacedRoom = rooms[current_id]
		for slot in current_room.world_door_slots:
			var other_id: int = slot["connected_to"]
			if other_id != -1 and not distances.has(other_id):
				distances[other_id] = distances[current_id] + 1
				queue.append(other_id)
	return distances

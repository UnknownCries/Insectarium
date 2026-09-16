extends Node

const QUERIES_PER_TEMPLATE: int = 200

const GRID_STEP: float = 24.0

var _normal_templates: Array[RoomTemplate] = []


func _ready() -> void:
	if not _load_templates_from_game_scene():
		return

	print("=".repeat(78))
	print("INSECTARIUM - A* PATHFINDING BENCHMARK")
	print("=".repeat(78))
	print("Godot: %s" % Engine.get_version_info().string)
	print("Templates measured: %d   Queries per template: %d" % [_normal_templates.size(), QUERIES_PER_TEMPLATE])
	print("")

	var rows: Array[Dictionary] = []
	for template in _normal_templates:
		var row := await _measure_template(template)
		if not row.is_empty():
			rows.append(row)

	_print_per_template_table(rows)
	_print_grouped_by_size(rows)
	_print_csv(rows)

	print("")
	print("Benchmark finished.")

	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()


func _load_templates_from_game_scene() -> bool:
	var scene: PackedScene = load("res://dungeon.tscn")
	if scene == null:
		push_error("A* benchmark: could not load res://dungeon.tscn")
		return false
	var root: Node = scene.instantiate()
	_normal_templates.assign(root.normal_templates)
	root.free()
	if _normal_templates.is_empty():
		push_error("A* benchmark: dungeon.tscn has no normal_templates assigned")
		return false
	return true

func _measure_template(template: RoomTemplate) -> Dictionary:
	if template == null or template.scene == null:
		return {}

	var placed := PlacedRoom.new(template, Vector2i.ZERO, 0)
	var room_node: Node = template.scene.instantiate()
	add_child(room_node)

	
	room_node.setup_room(placed, null)
	await get_tree().process_frame

	var build_t0 := Time.get_ticks_usec()
	room_node._setup_astar_grid(placed)
	var build_t1 := Time.get_ticks_usec()

	var astar: AStarGrid2D = room_node.astar
	if astar == null:
		room_node.queue_free()
		return {}

	var walkable := _collect_walkable(astar)
	var total_points: int = astar.region.size.x * astar.region.size.y
	var components := _walkable_components(astar, walkable)

	var query_times: Array[float] = []
	var path_lengths: Array[int] = []
	var failures: int = 0

	if walkable.size() >= 2:
		for i in QUERIES_PER_TEMPLATE:
			var a: Vector2i = walkable[randi() % walkable.size()]
			var b: Vector2i = walkable[randi() % walkable.size()]
			if a == b:
				continue
			var t0 := Time.get_ticks_usec()
			var path: PackedVector2Array = astar.get_point_path(a, b)
			var t1 := Time.get_ticks_usec()
			query_times.append(float(t1 - t0) / 1000.0)
			if path.is_empty():
				failures += 1
			else:
				path_lengths.append(path.size())

	room_node.queue_free()

	return {
		"name": _template_name(template),
		"cells": template.footprint.size(),
		"obstacles": template.obstacles.size(),
		"grid_points": total_points,
		"walkable_points": walkable.size(),
		"components": components.size(),
		"largest_component": components[0] if not components.is_empty() else 0,
		"stranded_points": walkable.size() - (components[0] if not components.is_empty() else 0),
		"solid_ratio": (1.0 - float(walkable.size()) / float(total_points)) if total_points > 0 else 0.0,
		"build_ms": float(build_t1 - build_t0) / 1000.0,
		"query_mean_ms": _mean(query_times),
		"query_max_ms": query_times.max() if not query_times.is_empty() else 0.0,
		"queries": query_times.size(),
		"failures": failures,
		"path_len_mean": _mean_int(path_lengths),
	}


func _collect_walkable(astar: AStarGrid2D) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for x in range(astar.region.position.x, astar.region.end.x):
		for y in range(astar.region.position.y, astar.region.end.y):
			var pt := Vector2i(x, y)
			if not astar.is_point_solid(pt):
				points.append(pt)
	return points

func _walkable_components(astar: AStarGrid2D, walkable: Array[Vector2i]) -> Array[int]:
	var free_set := {}
	for pt in walkable:
		free_set[pt] = true

	var seen := {}
	var sizes: Array[int] = []
	const ORTHOGONAL := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	const DIAGONAL := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

	for start in walkable:
		if seen.has(start):
			continue
		var size := 0
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var current: Vector2i = queue.pop_back()
			size += 1
			for d in ORTHOGONAL:
				var n: Vector2i = current + d
				if free_set.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
			for d in DIAGONAL:
				var n: Vector2i = current + d
				if not free_set.has(n) or seen.has(n):
					continue
				# The diagonal is only usable if neither orthogonal cell it
				# squeezes past is solid.
				if not free_set.has(Vector2i(current.x + d.x, current.y)):
					continue
				if not free_set.has(Vector2i(current.x, current.y + d.y)):
					continue
				seen[n] = true
				queue.append(n)
		sizes.append(size)

	sizes.sort()
	sizes.reverse()
	return sizes



func _template_name(template: RoomTemplate) -> String:
	if template.resource_path.is_empty():
		return "inline_%dx_cells" % template.footprint.size()
	return template.resource_path.get_file().get_basename()


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


func _print_per_template_table(rows: Array[Dictionary]) -> void:
	print("-".repeat(78))
	print("%-30s %5s %4s %7s %7s %8s %9s %6s %5s %8s" % ["template", "cells", "obs", "points", "solid%", "build ms", "query ms", "comp", "strnd", "fail"])
	print("-".repeat(78))
	for r in rows:
		print("%-30s %5d %4d %7d %6.1f%% %8.3f %9.4f %6d %5d %8d" % [
			r["name"], r["cells"], r["obstacles"], r["grid_points"],
			r["solid_ratio"] * 100.0, r["build_ms"], r["query_mean_ms"],
			r["components"], r["stranded_points"], r["failures"],
		])
	print("")


func _print_grouped_by_size(rows: Array[Dictionary]) -> void:
	var groups := {}
	for r in rows:
		var key: int = r["cells"]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(r)

	var keys: Array = groups.keys()
	keys.sort()

	print("-".repeat(78))
	print("Grouped by room size (number of 320x180 grid cells)")
	print("-".repeat(78))
	print("%-8s %-10s %9s %10s %11s %10s %7s" % ["cells", "templates", "points", "build ms", "query ms", "path len", "fail%"])
	for k in keys:
		var group: Array = groups[k]
		var build: Array[float] = []
		var query: Array[float] = []
		var points: Array[int] = []
		var lengths: Array[float] = []
		var total_queries := 0
		var total_failures := 0
		for r in group:
			build.append(r["build_ms"])
			query.append(r["query_mean_ms"])
			points.append(r["grid_points"])
			lengths.append(r["path_len_mean"])
			total_queries += r["queries"]
			total_failures += r["failures"]
		print("%-8d %-10d %9.0f %10.3f %11.4f %10.1f %6.2f%%" % [
			k, group.size(), _mean_int(points), _mean(build), _mean(query), _mean(lengths),
			(100.0 * float(total_failures) / float(total_queries)) if total_queries > 0 else 0.0,
		])
	print("")


func _print_csv(rows: Array[Dictionary]) -> void:
	print("=".repeat(78))
	print("CSV - per template")
	print("=".repeat(78))
	print("template,cells,obstacles,grid_points,walkable_points,solid_pct,build_ms,query_mean_ms,query_max_ms,queries,failures,fail_pct,components,largest_component,stranded_points,path_len_mean")
	for r in rows:
		print("%s,%d,%d,%d,%d,%.2f,%.4f,%.4f,%.4f,%d,%d,%.2f,%d,%d,%d,%.2f" % [
			r["name"], r["cells"], r["obstacles"], r["grid_points"], r["walkable_points"],
			r["solid_ratio"] * 100.0, r["build_ms"], r["query_mean_ms"], r["query_max_ms"],
			r["queries"], r["failures"],
			(100.0 * float(r["failures"]) / float(r["queries"])) if r["queries"] > 0 else 0.0,
			r["components"], r["largest_component"], r["stranded_points"],
			r["path_len_mean"],
		])

	_print_fragmented(rows)

func _print_fragmented(rows: Array[Dictionary]) -> void:
	print("")
	print("=".repeat(78))
	print("TEMPLATES WITH A FRAGMENTED WALKABLE GRID")
	print("=".repeat(78))
	var found := false
	for r in rows:
		if r["components"] > 1:
			found = true
			print("  %-30s components=%d  walkable=%d  largest=%d  stranded=%d  failed queries=%d/%d (%.1f%%)" % [
				r["name"], r["components"], r["walkable_points"], r["largest_component"],
				r["stranded_points"], r["failures"], r["queries"],
				(100.0 * float(r["failures"]) / float(r["queries"])) if r["queries"] > 0 else 0.0,
			])
	if not found:
		print("  none - every template's walkable grid is a single connected region")

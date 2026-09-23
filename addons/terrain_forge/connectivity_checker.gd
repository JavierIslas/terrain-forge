# Terrain Forge
# Copyright (C) 2026 Javier Islas
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version. This program is distributed WITHOUT ANY WARRANTY; see the GNU
# AGPL for details: <https://www.gnu.org/licenses/>.
#
# A commercial license that exempts you from the AGPL is available: see
# LICENSE_COMMERCIAL.md or contact islasjavieralf@gmail.com.

class_name ConnectivityChecker
extends RefCounted
## Conectividad del terreno pasable sobre cualquier topología.
##
## analyze() hace BFS flood-fill y reporta componentes en orden determinista
## (tamaño desc, primera coordenada asc). repair() conecta cada componente
## menor con la mayor tallando corredores (celdas no pasables → PLAINS) sobre
## topology.line(). Los checks de pasabilidad se evalúan EN VIVO, así los
## corredores previos cuentan para los siguientes.
##
## line() puede incluir waypoints fuera del grid (el redondeo de la
## interpolación hex sale del rectángulo odd-r aunque los extremos sean
## válidos): se saltan, y si dos waypoints válidos consecutivos quedan a
## distancia > 1 se tiende un puente contiguo por vecinos — sin él, el
## corredor queda agujereado y la componente sigue desconectada.

const MODE_REPORT := "report"
const MODE_REPAIR := "repair"


## Analiza las componentes conexas del terreno pasable.
## [param passable_fn]: (coord: Vector2i) -> bool; default: terrain != WATER.
## Retorna { is_connected, regions (Array de Array[Vector2i]), region_sizes,
## largest_ratio, largest_coords }.
static func analyze(topology: GridTopology, passable_fn: Callable = Callable()) -> Dictionary:
	var is_passable := _resolve_passable(topology, passable_fn)
	var visited := {}
	var regions: Array = []
	for coord in topology.get_all_coords():
		if visited.has(coord) or not is_passable.call(coord):
			continue
		regions.append(_flood_region(topology, coord, is_passable, visited))
	_sort_regions(regions)
	return _build_report(topology, regions)


## Conecta cada componente menor con la mayor tallando corredores vía line()
## (endpoint: primera coord de la menor, coord de la mayor más cercana a esa).
## Retorna el análisis POST-reparación + "repaired" (celdas convertidas).
static func repair(topology: GridTopology, passable_fn: Callable = Callable()) -> Dictionary:
	var analysis := analyze(topology, passable_fn)
	if analysis.is_connected:
		analysis.repaired = 0
		return analysis
	var is_passable := _resolve_passable(topology, passable_fn)
	var repaired := 0
	var largest: Array = analysis.regions[0]
	for i in range(1, analysis.regions.size()):
		var smaller: Array = analysis.regions[i]
		repaired += _carve_corridor(topology, is_passable, smaller[0], largest)
	var after := analyze(topology, passable_fn)
	after.repaired = repaired
	return after


## Default de pasabilidad: terreno != WATER (lectura en vivo de la topología).
static func _resolve_passable(topology: GridTopology, passable_fn: Callable) -> Callable:
	if passable_fn.is_valid():
		return passable_fn
	return func(coord: Vector2i) -> bool:
		return topology.get_terrain(coord) != MapCell.Terrain.WATER


## BFS sobre vecinos válidos y pasables aún no visitados.
static func _flood_region(topology: GridTopology, start: Vector2i, is_passable: Callable, visited: Dictionary) -> Array[Vector2i]:
	var region: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var coord: Vector2i = queue.pop_front()
		region.append(coord)
		for neighbor in topology.get_neighbors(coord):
			if topology.is_valid(neighbor) and not visited.has(neighbor) and is_passable.call(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return region


## Orden determinista: tamaño descendente, primera coordenada ascendente.
static func _sort_regions(regions: Array) -> void:
	regions.sort_custom(func(a: Array, b: Array) -> bool:
		if a.size() != b.size():
			return a.size() > b.size()
		return _first_coord(a) < _first_coord(b))


static func _first_coord(region: Array) -> Vector2i:
	return region[0]


static func _build_report(topology: GridTopology, regions: Array) -> Dictionary:
	var sizes: Array = []
	var total_passable := 0
	for region in regions:
		sizes.append(region.size())
		total_passable += region.size()
	var largest_size: int = sizes[0] if not sizes.is_empty() else 0
	var largest_ratio := float(largest_size) / float(total_passable) if total_passable > 0 else 0.0
	return {
		"is_connected": regions.size() <= 1,
		"regions": regions,
		"region_sizes": sizes,
		"largest_ratio": largest_ratio,
		"largest_coords": regions[0] if not regions.is_empty() else [],
	}


## Corredor desde [param target] (componente menor) hacia la coord de
## [param largest] más cercana; convierte celdas no pasables a PLAINS.
## line() puede devolver waypoints fuera del grid (contrato del puerto): se
## saltan, y si al retomar quedan a distancia > 1 del último tallado se
## tiende un puente contiguo — sin él, el corredor queda agujereado y la
## componente sigue desconectada (~1/150 seeds hex).
static func _carve_corridor(topology: GridTopology, is_passable: Callable, target: Vector2i, largest: Array) -> int:
	var anchor := _closest_coord(topology, target, largest)
	var carved := 0
	var previous := anchor
	for coord in topology.line(anchor, target):
		if not topology.is_valid(coord):
			continue
		if topology.distance(previous, coord) > 1:
			carved += _carve_bridge(topology, is_passable, previous, coord)
		carved += _carve_cell(topology, is_passable, coord)
		previous = coord
	return carved


## Convierte la celda a PLAINS si no es pasable (check en vivo: los corredores
## previos cuentan para los siguientes). Retorna 1 si talló, 0 si no.
static func _carve_cell(topology: GridTopology, is_passable: Callable, coord: Vector2i) -> int:
	if is_passable.call(coord):
		return 0
	topology.set_terrain(coord, MapCell.Terrain.PLAINS)
	return 1


## Puente contiguo entre dos waypoints válidos que line() dejó a distancia
## > 1. Caminata greedy determinista: entra siempre al vecino válido no
## visitado más cercano al objetivo (empates por x, y — mismo orden total
## del heap de RoadBuilder._trace). Terminación estructural: cada paso marca
## una celda nueva (cota cell_count); sin candidatos se corta y degrada al
## hueco previo; el report post-repair ya informa is_connected al caller.
static func _carve_bridge(topology: GridTopology, is_passable: Callable, origin: Vector2i, goal: Vector2i) -> int:
	var carved := 0
	var current := origin
	var visited := {origin: true}
	while current != goal:
		var candidates := _unvisited_neighbors(topology, current, visited)
		if candidates.is_empty():
			break
		candidates.sort_custom(_by_distance_to(topology, goal))
		current = candidates[0]
		visited[current] = true
		carved += _carve_cell(topology, is_passable, current)
	return carved


## Vecinos de [param current] válidos y aún no visitados por el puente.
static func _unvisited_neighbors(topology: GridTopology, current: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for neighbor in topology.get_neighbors(current):
		if topology.is_valid(neighbor) and not visited.has(neighbor):
			candidates.append(neighbor)
	return candidates


## Comparador (distance al objetivo, x, y): orden total sobre coordenadas
## distintas → resultado de sort único sin depender de estabilidad, sin rng.
static func _by_distance_to(topology: GridTopology, goal: Vector2i) -> Callable:
	return func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a := topology.distance(a, goal)
		var distance_b := topology.distance(b, goal)
		if distance_a != distance_b:
			return distance_a < distance_b
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y


static func _closest_coord(topology: GridTopology, target: Vector2i, coords: Array) -> Vector2i:
	var closest: Vector2i = coords[0]
	var best := topology.distance(target, closest)
	for coord in coords:
		var candidate := topology.distance(target, coord)
		if candidate < best:
			best = candidate
			closest = coord
	return closest

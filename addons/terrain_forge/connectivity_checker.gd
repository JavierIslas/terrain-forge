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
static func _carve_corridor(topology: GridTopology, is_passable: Callable, target: Vector2i, largest: Array) -> int:
	var anchor := _closest_coord(topology, target, largest)
	var carved := 0
	for coord in topology.line(anchor, target):
		if topology.is_valid(coord) and not is_passable.call(coord):
			topology.set_terrain(coord, MapCell.Terrain.PLAINS)
			carved += 1
	return carved


static func _closest_coord(topology: GridTopology, target: Vector2i, coords: Array) -> Vector2i:
	var closest: Vector2i = coords[0]
	var best := topology.distance(target, closest)
	for coord in coords:
		var candidate := topology.distance(target, coord)
		if candidate < best:
			best = candidate
			closest = coord
	return closest

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

class_name RiverCarver
extends RefCounted
## Ríos como caminos sobre la topología, con nacimientos en elevación alta
## separados por distancia mínima y caminata con sesgos opcionales.
##
## Con los defaults (downhill_bias 0.0, straightness 0.0) la caminata es un
## random walk sin repetir celdas — mismo espíritu que los ríos del anfitrión,
## pero determinista vía SeededRng y con mejoras opt-in por params.

## Distancia topológica mínima entre nacimientos (default).
const RIVER_SPACING_DEFAULT := 3
const RIVER_COUNT_DEFAULT := 3
const RIVER_LENGTH_MIN := 4
const RIVER_LENGTH_MAX := 10


## Talla [param river_count] ríos y materializa edges RIVER entre celdas
## consecutivas de cada camino. Retorna Array de Array[Vector2i] (los caminos,
## para reporte/snapshot; no tipable anidado en GDScript).
## params: "river_count" (3), "river_spacing" (3), "river_length_min" (4),
## "river_length_max" (10), "river_downhill_bias" (0.0), "river_straightness" (0.0).
static func carve(topology: GridTopology, rng: SeededRng, params: Dictionary = {}) -> Array:
	var paths: Array = []
	for start in _pick_starts(topology, rng, params):
		var steps := rng.randi_range(
			int(params.get("river_length_min", RIVER_LENGTH_MIN)),
			int(params.get("river_length_max", RIVER_LENGTH_MAX)))
		var path := _walk(topology, rng, start, steps, params)
		for j in path.size() - 1:
			topology.set_edge(path[j], path[j + 1], SquareGrid.EdgeType.RIVER)
		if path.size() >= 2:
			paths.append(path)
	return paths


## Nacimientos: candidatos de la mitad más alta de elevaciones (si hay
## elevación escrita), barajados con el rng, aceptados respetando el spacing.
## Sin elevación (todo 0.0) el filtro deja pasar todo — comportamiento degrade.
static func _pick_starts(topology: GridTopology, rng: SeededRng, params: Dictionary) -> Array[Vector2i]:
	var wanted := int(params.get("river_count", RIVER_COUNT_DEFAULT))
	var spacing := int(params.get("river_spacing", RIVER_SPACING_DEFAULT))
	var candidates := _filter_high_elevation(topology, rng.shuffled(topology.get_all_coords()))
	var starts: Array[Vector2i] = []
	for coord in candidates:
		if starts.size() >= wanted:
			break
		if _far_enough(topology, coord, starts, spacing):
			starts.append(coord)
	return starts


static func _filter_high_elevation(topology: GridTopology, candidates: Array) -> Array:
	var elevations: Array[float] = []
	for coord in candidates:
		elevations.append(topology.get_elevation(coord))
	elevations.sort()
	var median := elevations[elevations.size() / 2] if not elevations.is_empty() else 0.0
	var filtered: Array[Vector2i] = []
	for coord in candidates:
		if topology.get_elevation(coord) >= median:
			filtered.append(coord)
	return filtered


## Caminata sin repetir celdas; corta antes si queda encerrada por el borde
## o por celdas ya visitadas (mismo contrato que el walk del anfitrión).
static func _walk(topology: GridTopology, rng: SeededRng, start: Vector2i, steps: int, params: Dictionary) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var visited := {start: true}
	var current := start
	var last_direction := Vector2i.ZERO
	for _i in steps:
		var candidates := _unvisited_neighbors(topology, current, visited)
		if candidates.is_empty():
			break
		var next := _pick_next(topology, rng, current, last_direction, candidates, params)
		last_direction = next - current
		visited[next] = true
		path.append(next)
		current = next
	return path


static func _unvisited_neighbors(topology: GridTopology, coord: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var valid: Array[Vector2i] = []
	for neighbor in topology.get_neighbors(coord):
		if topology.is_valid(neighbor) and not visited.has(neighbor):
			valid.append(neighbor)
	return valid


## Mejor puntaje: aleatorio base + sesgo de descenso + bonus de rectitud
## (continuar en la dirección del último paso). Todos los términos se
## evalúan por candidato consumiendo el rng → determinismo exacto.
static func _pick_next(topology: GridTopology, rng: SeededRng, current: Vector2i, last_direction: Vector2i, candidates: Array[Vector2i], params: Dictionary) -> Vector2i:
	var downhill_bias: float = float(params.get("river_downhill_bias", 0.0))
	var straightness: float = float(params.get("river_straightness", 0.0))
	var current_elevation := topology.get_elevation(current)
	var best: Vector2i = candidates[0]
	var best_score := -1.0
	for candidate in candidates:
		var score := rng.randf_range(0.0, 1.0)
		if downhill_bias > 0.0:
			score += downhill_bias * clampf(current_elevation - topology.get_elevation(candidate), 0.0, 1.0)
		if straightness > 0.0 and last_direction != Vector2i.ZERO and candidate - current == last_direction:
			score += straightness
		if score > best_score:
			best_score = score
			best = candidate
	return best


static func _far_enough(topology: GridTopology, coord: Vector2i, chosen: Array[Vector2i], spacing: int) -> bool:
	for other in chosen:
		if topology.distance(coord, other) < spacing:
			return false
	return true

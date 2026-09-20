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

class_name LocationPlacer
extends RefCounted
## Esparcido de locations con filtro de terreno y spacing mínimo opcional.
##
## El orden de selección es Fisher-Yates con el SeededRng del stage (nunca el
## RNG global). Con spacing > 0 los candidatos demasiado cercanos se descartan
## sin reintento: se pueden colocar menos que location_count (determinista).


## Coloca hasta location_count locations y retorna las coordenadas en orden
## de colocación. params: "location_count" (0), "location_type" (1),
## "location_terrain_filter" (Array[int], vacío = todas las celdas),
## "location_spacing" (0 = sin check; distancia topológica mínima).
static func place(topology: GridTopology, rng: SeededRng, params: Dictionary = {}) -> Array[Vector2i]:
	var count := int(params.get("location_count", 0))
	var location_type := int(params.get("location_type", 1))
	var terrain_filter: Array = params.get("location_terrain_filter", [])
	var spacing := int(params.get("location_spacing", 0))
	var placed: Array[Vector2i] = []
	for coord in rng.shuffled(_candidates(topology, terrain_filter)):
		if placed.size() >= count:
			break
		if spacing > 0 and not _far_enough(topology, coord, placed, spacing):
			continue
		topology.set_location(coord, location_type)
		placed.append(coord)
	return placed


## Candidatas: pasan el filtro de terreno y no tienen location previa.
static func _candidates(topology: GridTopology, terrain_filter: Array) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for coord in topology.get_all_coords():
		if not terrain_filter.is_empty() and not topology.get_terrain(coord) in terrain_filter:
			continue
		if topology.has_location(coord):
			continue
		candidates.append(coord)
	return candidates


static func _far_enough(topology: GridTopology, coord: Vector2i, chosen: Array[Vector2i], spacing: int) -> bool:
	for other in chosen:
		if topology.distance(coord, other) < spacing:
			return false
	return true

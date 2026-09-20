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

class_name TerrainClassifier
extends RefCounted
## Clasificación de un buffer de alturas a terrenos + smoothing por mayoría.
##
## La escalera de 5 bandas replica exactamente la del anfitrión (orden y
## umbrales), de modo que la paridad bit a bit por seed queda congelada por
## test. classify_fn del perfil, si está seteado, reemplaza la escalera.


## Escalera de 5 bandas sobre [param value]:
## < water_level → WATER; > mountain_level → MOUNTAIN; > forest_level → FOREST;
## > 0.0 → ROAD; resto → PLAINS.
## classify_fn del perfil, si es válido, reemplaza la escalera con firma
## (value: float, moisture: float) -> int (moisture 0.0 si no se sampleó).
static func classify_value(value: float, profile: BiomeProfile, moisture: float = 0.0) -> int:
	if profile.classify_fn.is_valid():
		return int(profile.classify_fn.call(value, moisture))
	if value < profile.water_level:
		return MapCell.Terrain.WATER
	if value > profile.mountain_level:
		return MapCell.Terrain.MOUNTAIN
	if value > profile.forest_level:
		return MapCell.Terrain.FOREST
	if value > 0.0:
		return MapCell.Terrain.ROAD
	return MapCell.Terrain.PLAINS


## Clasifica el buffer de alturas completo (row-major) a clases de terreno.
## [param moisture] opcional del mismo largo que heights (row-major).
static func classify_buffer(heights: PackedFloat32Array, profile: BiomeProfile, moisture: PackedFloat32Array = PackedFloat32Array()) -> PackedInt32Array:
	var classes := PackedInt32Array()
	classes.resize(heights.size())
	for i in heights.size():
		var cell_moisture := moisture[i] if i < moisture.size() else 0.0
		classes[i] = classify_value(heights[i], profile, cell_moisture)
	return classes


## Suavizado por mayoría: [param passes] pasadas donde cada celda adopta el
## terreno mayoritario de su vecindario (vecinos válidos + la propia celda).
## Empate → conserva el terreno actual. Cada pasada lee un snapshot (doble
## buffer), así el resultado es independiente del orden de iteración.
static func apply_smoothing(topology: GridTopology, passes: int) -> void:
	for _pass in maxi(passes, 0):
		var snapshot := _terrain_snapshot(topology)
		for coord in topology.get_all_coords():
			var majority := _majority_terrain(topology, coord, snapshot)
			if majority != snapshot[coord]:
				topology.set_terrain(coord, majority)


static func _terrain_snapshot(topology: GridTopology) -> Dictionary:
	var snapshot := {}
	for coord in topology.get_all_coords():
		snapshot[coord] = topology.get_terrain(coord)
	return snapshot


## Vecinos válidos + propia celda; empate entre máximos → terreno actual.
static func _majority_terrain(topology: GridTopology, coord: Vector2i, snapshot: Dictionary) -> int:
	var counts := {}
	var current: int = snapshot[coord]
	counts[current] = 1
	for neighbor in topology.get_neighbors(coord):
		if topology.is_valid(neighbor):
			var terrain: int = snapshot[neighbor]
			counts[terrain] = counts.get(terrain, 0) + 1
	var best: int = current
	var best_count: int = 1
	var has_tie := false
	for terrain in counts:
		if counts[terrain] > best_count:
			best = terrain
			best_count = counts[terrain]
			has_tie = false
		elif counts[terrain] == best_count and terrain != best:
			has_tie = true
	return current if has_tie else best

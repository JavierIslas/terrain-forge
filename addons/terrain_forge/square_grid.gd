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

class_name SquareGrid
extends RefCounted
## Grid de celdas cuadradas: espejo de la mitad agnóstica de topología que la
## investigación verificó en el grid hexagonal del anfitrión (almacenamiento
## rectangular por Vector2i, costos extensibles, edges con clave simétrica,
## serialize). Sin niebla ni pathfinding: esos consumos pertenecen al anfitrión.

enum EdgeType { NONE, RIVER, ROAD, WALL, CUSTOM }

## Costos espejo del anfitrión (claves int extensibles; -1.0 = intransitable).
const TERRAIN_COST: Dictionary = {
	MapCell.Terrain.ROAD: 1.0,
	MapCell.Terrain.PLAINS: 1.5,
	MapCell.Terrain.FOREST: 2.0,
	MapCell.Terrain.MOUNTAIN: 3.0,
	MapCell.Terrain.WATER: -1.0,
}

const EDGE_COST: Dictionary = {
	EdgeType.RIVER: 2.0,
	EdgeType.WALL: -1.0,
	EdgeType.ROAD: -0.5,
}

## Lado del tile en píxeles (renderizado de demos; la generación no lo usa).
const TILE_SIZE: float = 32.0

var width: int = 0
var height: int = 0
var cells: Dictionary = {}  # Vector2i → MapCell
var edges: Dictionary = {}  # String (edge_key) → Dictionary { type: int, cost: float }
var terrain_cost: Dictionary = {}
var edge_cost: Dictionary = {}
var cell_size: float = TILE_SIZE


func _init(map_width: int = 15, map_height: int = 15, cost_table: Dictionary = {}, size: float = 0.0, edge_cost_table: Dictionary = {}) -> void:
	if map_width <= 0 or map_height <= 0:
		push_error("SquareGrid: dimensiones inválidas (%d x %d), se usará 15x15" % [map_width, map_height])
		map_width = 15
		map_height = 15
	width = map_width
	height = map_height
	terrain_cost = cost_table if cost_table else TERRAIN_COST
	edge_cost = edge_cost_table if edge_cost_table else EDGE_COST
	cell_size = size if size > 0.0 else TILE_SIZE


## Genera las celdas del grid con [param default_terrain]. Limpia las previas.
func generate_cells(default_terrain: int = MapCell.Terrain.PLAINS) -> void:
	cells.clear()
	for y in height:
		for x in width:
			cells[Vector2i(x, y)] = MapCell.new(Vector2i(x, y), default_terrain)


## Retorna la MapCell en [param coord], o null si la coordenada no existe.
func get_cell(coord: Vector2i) -> MapCell:
	return cells.get(coord, null)


## Retorna el diccionario completo de celdas (Vector2i → MapCell).
func get_all_cells() -> Dictionary:
	return cells


## Asigna el terreno de la celda en [param coord]. Sin efecto si no existe.
func set_terrain(coord: Vector2i, terrain: int) -> void:
	var cell := get_cell(coord)
	if cell:
		cell.terrain = terrain


## Retorna true si [param coord] existe en el grid.
func is_valid(coord: Vector2i) -> bool:
	return cells.has(coord)


## Clave canónica simétrica para un edge (mismo esquema que el anfitrión).
static func edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


## Define un edge entre [param a] y [param b]. Si ya existe, lo reemplaza.
## [param properties] se duplica: el edge no comparte estado con el caller.
func set_edge(a: Vector2i, b: Vector2i, edge_type: int, properties: Dictionary = {}) -> void:
	var edge := properties.duplicate()
	edge["type"] = edge_type
	if not edge.has("cost"):
		edge["cost"] = edge_cost.get(edge_type, 0.0)
	edges[edge_key(a, b)] = edge


## Retorna el Dictionary del edge entre [param a] y [param b], o {} si no existe.
func get_edge(a: Vector2i, b: Vector2i) -> Dictionary:
	return edges.get(edge_key(a, b), {})


## Retorna true si hay un edge definido entre [param a] y [param b].
func has_edge(a: Vector2i, b: Vector2i) -> bool:
	return edges.has(edge_key(a, b))


## Elimina el edge entre [param a] y [param b] si existe.
func remove_edge(a: Vector2i, b: Vector2i) -> void:
	edges.erase(edge_key(a, b))


## Esquina superior izquierda del tile en píxeles (para demos de render).
static func offset_to_pixel(coord: Vector2i, size: float = TILE_SIZE) -> Vector2:
	return Vector2(coord.x * size, coord.y * size)


## Serializa el grid completo a un Dictionary compatible con JSON.
func serialize() -> Dictionary:
	var cells_data: Array = []
	for coord in cells:
		cells_data.append(cells[coord].serialize())
	var edges_data: Dictionary = {}
	for key in edges:
		edges_data[key] = edges[key].duplicate()
	return {
		"width": width,
		"height": height,
		"terrain_cost": terrain_cost.duplicate(),
		"edge_cost": edge_cost.duplicate(),
		"cell_size": cell_size,
		"cells": cells_data,
		"edges": edges_data,
	}


## Reconstruye un SquareGrid desde un Dictionary generado por serialize().
## NOTA: JSON serializa int keys como strings; se reconvierten aquí.
static func deserialize(data: Dictionary) -> SquareGrid:
	var parsed_terrain_cost: Dictionary = {}
	for key in data.get("terrain_cost", {}):
		parsed_terrain_cost[int(key)] = data["terrain_cost"][key]
	var parsed_edge_cost: Dictionary = {}
	for key in data.get("edge_cost", {}):
		parsed_edge_cost[int(key)] = data["edge_cost"][key]
	var grid := SquareGrid.new(data.get("width", 15), data.get("height", 15), parsed_terrain_cost, data.get("cell_size", TILE_SIZE), parsed_edge_cost)
	grid.cells.clear()
	for cell_data in data.get("cells", []):
		var cell := MapCell.deserialize(cell_data)
		grid.cells[cell.coord] = cell
	var edges_data: Dictionary = data.get("edges", {})
	for key in edges_data:
		var entry = edges_data[key]
		if entry is Dictionary and entry.has("type") and entry.has("cost"):
			grid.edges[key] = entry
		else:
			push_warning("SquareGrid.deserialize: edge inválido '%s' descartado" % key)
	return grid

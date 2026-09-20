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

class_name SquareTopology
extends GridTopology
## Topología de cuadrados sobre un SquareGrid, sin dependencia del anfitrión.
##
## connectivity decide el vecindario y SU métrica (deben ser consistentes):
## CONNECTIVITY_VON_NEUMANN = 4 cardinales + distancia Manhattan + línea
## escalonada; CONNECTIVITY_MOORE = 8 vecinos + Chebyshev + Bresenham diagonal.

const CONNECTIVITY_VON_NEUMANN := 4
const CONNECTIVITY_MOORE := 8

var grid: SquareGrid
var connectivity: int


func _init(square_grid: SquareGrid, cell_connectivity: int = CONNECTIVITY_VON_NEUMANN) -> void:
	grid = square_grid
	connectivity = cell_connectivity


func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	if connectivity == CONNECTIVITY_MOORE:
		return [
			Vector2i(coord.x - 1, coord.y - 1), Vector2i(coord.x, coord.y - 1),
			Vector2i(coord.x + 1, coord.y - 1), Vector2i(coord.x - 1, coord.y),
			Vector2i(coord.x + 1, coord.y), Vector2i(coord.x - 1, coord.y + 1),
			Vector2i(coord.x, coord.y + 1), Vector2i(coord.x + 1, coord.y + 1),
		]
	return [
		Vector2i(coord.x - 1, coord.y), Vector2i(coord.x + 1, coord.y),
		Vector2i(coord.x, coord.y - 1), Vector2i(coord.x, coord.y + 1),
	]


func is_valid(coord: Vector2i) -> bool:
	return grid.is_valid(coord)


func distance(a: Vector2i, b: Vector2i) -> int:
	if connectivity == CONNECTIVITY_MOORE:
		return maxi(absi(b.x - a.x), absi(b.y - a.y))
	return absi(b.x - a.x) + absi(b.y - a.y)


func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if connectivity == CONNECTIVITY_MOORE:
		return _line_bresenham(a, b)
	return _line_staircase(a, b)


func get_all_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	coords.assign(grid.cells.keys())
	coords.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
		return x.y < y.y or (x.y == y.y and x.x < y.x))
	return coords


func get_dimensions() -> Vector2i:
	return Vector2i(grid.width, grid.height)


func cell_count() -> int:
	return grid.cells.size()


func get_terrain(coord: Vector2i) -> int:
	var cell := grid.get_cell(coord)
	return cell.terrain if cell else -1


func set_terrain(coord: Vector2i, terrain: int) -> void:
	grid.set_terrain(coord, terrain)


func get_elevation(coord: Vector2i) -> float:
	var cell := grid.get_cell(coord)
	return cell.elevation if cell else 0.0


func set_elevation(coord: Vector2i, elevation: float) -> void:
	var cell := grid.get_cell(coord)
	if cell:
		cell.elevation = elevation


func set_location(coord: Vector2i, location_type: int) -> void:
	var cell := grid.get_cell(coord)
	if cell:
		cell.location_type = location_type


func has_location(coord: Vector2i) -> bool:
	var cell := grid.get_cell(coord)
	return cell.has_location() if cell else false


func set_edge(a: Vector2i, b: Vector2i, edge_type: int) -> void:
	grid.set_edge(a, b, edge_type)


func edge_count() -> int:
	return grid.edges.size()


func clear_edges(edge_type: int) -> int:
	var removed := 0
	for key in grid.edges.keys():
		if grid.edges[key].get("type", -1) == edge_type:
			grid.edges.erase(key)
			removed += 1
	return removed


## Escalera 4-conectada: avanza por el eje con mayor distancia restante
## (empate → x). Monótona y determinista; largo |dx| + |dy| + 1.
static func _line_staircase(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [a]
	var current := a
	while current != b:
		var dx := b.x - current.x
		var dy := b.y - current.y
		if absi(dx) >= absi(dy):
			current = Vector2i(current.x + signi(dx), current.y)
		else:
			current = Vector2i(current.x, current.y + signi(dy))
		path.append(current)
	return path


## Bresenham clásico con diagonales (8-conectado).
static func _line_bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [a]
	var x := a.x
	var y := a.y
	var step_x := signi(b.x - a.x)
	var step_y := signi(b.y - a.y)
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var err := dx + dy
	while Vector2i(x, y) != b:
		var doubled := 2 * err
		if doubled >= dy:
			err += dy
			x += step_x
		if doubled <= dx:
			err += dx
			y += step_y
		path.append(Vector2i(x, y))
	return path

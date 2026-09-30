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

class_name HexTopology
extends GridTopology
## Adaptador hex sobre el grid del anfitrión (hex_strategy_map).
##
## ÚNICO archivo del addon autorizado a depender del anfitrión (exento del
## guard por HOST_AWARE_FILES). Para que una instalación squares-only pueda
## parsear el addon completo, este archivo NO tipa contra clases del anfitrión:
## resuelve sus scripts con load() tras is_host_available(), y solo consume
## API pública del anfitrión (los privados como la línea hex se reimplementan
## aquí con las primitivas públicas offset_to_cube/cube_round).

const HOST_GRID_PATH := "res://addons/hex_strategy_map/hex_grid.gd"
const HOST_CELL_PATH := "res://addons/hex_strategy_map/hex_cell.gd"

## HexGrid del anfitrión, sin tipar estático (ver docblock de clase).
var grid
var _host_grid_script: GDScript


func _init(host_grid = null) -> void:
	if not is_host_available():
		push_error("HexTopology: el modo hex requiere hex_strategy_map (falta %s)" % HOST_GRID_PATH)
		grid = null
		return
	grid = host_grid
	_host_grid_script = load(HOST_GRID_PATH)


## true si el anfitrión está instalado en este proyecto.
static func is_host_available() -> bool:
	return ResourceLoader.exists(HOST_GRID_PATH) and ResourceLoader.exists(HOST_CELL_PATH)


## Pipeline completo del forge sobre un HexGrid NUEVO del anfitrión.
## Retorna el HexGrid (o null sin anfitrión). Los terrenos/elevación se
## escriben vía set_terrain del anfitrión (respeta su cache de heurística).
static func generate_hex(map_width: int, map_height: int, params: Dictionary = {}):
	if not is_host_available():
		push_error("HexTopology.generate_hex: anfitrión no disponible")
		return null
	var host_grid = _new_host_grid(map_width, map_height, params)
	TerrainForge.generate(HexTopology.new(host_grid), params)
	return host_grid


## Regenera sobre un HexGrid ya existente (p. ej. restaurado con deserialize).
## Semántica de regeneración completa: los stages del forge limpian los edges
## RIVER, las locations y — solo si corre con "roads": true — los edges ROAD
## previos antes de escribir los nuevos. Los edges de otros tipos (ROAD/WALL
## colocados por el juego) se preservan mientras el stage roads no corra.
static func apply(host_grid, params: Dictionary = {}) -> void:
	TerrainForge.generate(HexTopology.new(host_grid), params)


static func _new_host_grid(map_width: int, map_height: int, params: Dictionary):
	var host_lib := load(HOST_GRID_PATH)
	var host_grid = host_lib.new(
		map_width, map_height,
		params.get("cost_table", {}),
		params.get("hex_size", 0.0),
		params.get("edge_cost", {}))
	host_grid.generate_cells()
	return host_grid


# --- Geometría (delegada a las statics públicas del anfitrión) ---

func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	neighbors.assign(_host_grid_script.get_neighbors(coord))
	return neighbors


func is_valid(coord: Vector2i) -> bool:
	return grid.is_valid(coord)


func distance(a: Vector2i, b: Vector2i) -> int:
	return _host_grid_script.distance(a, b)


## Línea hex reimplementada con primitivas públicas (el anfitrión la tiene
## privada): interpolación cube + cube_round, extremos incluidos.
## Igual que la _hex_line del anfitrión (solo LOS, con null-checks), la
## interpolación + redondeo puede producir offsets FUERA del rectángulo
## odd-r aunque ambos extremos sean válidos (ej.: line((0,6),(0,8)) pasa
## por (-1,7)). NO se corrige aquí: es geometría pura espejo del anfitrión;
## filtrar con is_valid() y puentear los huecos es del consumidor.
func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var steps: int = distance(a, b)
	if steps == 0:
		result.append(a)
		return result
	var ca := _cube_to_float(_host_grid_script.offset_to_cube(a))
	var cb := _cube_to_float(_host_grid_script.offset_to_cube(b))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var lerped := Vector3(
			ca.x + (cb.x - ca.x) * t,
			ca.y + (cb.y - ca.y) * t,
			ca.z + (cb.z - ca.z) * t)
		var rounded: Vector3i = _host_grid_script.cube_round(lerped.x, lerped.z)
		result.append(_cube_to_offset(rounded))
	return result


static func _cube_to_float(cube: Vector3i) -> Vector3:
	return Vector3(float(cube.x), float(cube.y), float(cube.z))


## Cube → offset odd-r (fórmula estándar; el anfitrión la tiene privada).
static func _cube_to_offset(cube: Vector3i) -> Vector2i:
	var col := cube.x + ((cube.z - (cube.z & 1)) / 2)
	return Vector2i(col, cube.z)


# --- Iteración ---

func get_all_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	coords.assign(grid.get_all_cells().keys())
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return coords


func get_dimensions() -> Vector2i:
	return Vector2i(grid.width, grid.height)


func cell_count() -> int:
	return grid.get_all_cells().size()


# --- Storage (escrituras por la API pública del anfitrión) ---

func get_terrain(coord: Vector2i) -> int:
	var cell = grid.get_cell(coord)
	return cell.terrain if cell else -1


func set_terrain(coord: Vector2i, terrain: int) -> void:
	grid.set_terrain(coord, terrain)


func get_elevation(coord: Vector2i) -> float:
	var cell = grid.get_cell(coord)
	return cell.elevation if cell else 0.0


func set_elevation(coord: Vector2i, elevation: float) -> void:
	var cell = grid.get_cell(coord)
	if cell:
		cell.elevation = elevation


func set_location(coord: Vector2i, location_type: int) -> void:
	var cell = grid.get_cell(coord)
	if cell:
		cell.location_type = location_type


func has_location(coord: Vector2i) -> bool:
	var cell = grid.get_cell(coord)
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


# --- Costos (delegados a la resolución del anfitrión, cache incluida) ---

func get_movement_cost(coord: Vector2i) -> float:
	return grid.get_movement_cost(coord)


func is_passable(coord: Vector2i) -> bool:
	return grid.is_passable(coord)


func get_edge_cost(a: Vector2i, b: Vector2i) -> float:
	return grid.get_edge_cost(a, b)

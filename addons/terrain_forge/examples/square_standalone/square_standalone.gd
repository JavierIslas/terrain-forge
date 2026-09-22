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

extends Node2D
## Demo standalone: generación sobre cuadrados SIN el anfitrión instalado.
## Click regenera con la siguiente seed (contador, sin RNG global).

const MAP_WIDTH := 34
const MAP_HEIGHT := 22
const TILE := 20.0

const TERRAIN_COLORS := {
	MapCell.Terrain.WATER: Color(0.24, 0.44, 0.64),
	MapCell.Terrain.PLAINS: Color(0.56, 0.72, 0.40),
	MapCell.Terrain.FOREST: Color(0.28, 0.52, 0.30),
	MapCell.Terrain.MOUNTAIN: Color(0.58, 0.55, 0.50),
	MapCell.Terrain.ROAD: Color(0.76, 0.68, 0.46),
}

var grid: SquareGrid
var next_seed := 0


func _ready() -> void:
	_regenerate()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_regenerate()


func _regenerate() -> void:
	next_seed += 1
	grid = SquareGrid.new(MAP_WIDTH, MAP_HEIGHT)
	grid.generate_cells()
	TerrainForge.generate(SquareTopology.new(grid), {
		"seed": next_seed,
		"island_falloff": 0.35,
		"smoothing_passes": 1,
		"river_count": 2,
		"river_water": true,
		"location_count": 3,
		"location_spacing": 3,
		"roads": true,
	})
	queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	for coord in grid.get_all_cells():
		var cell: MapCell = grid.get_all_cells()[coord]
		var rect := Rect2(Vector2(coord) * TILE, Vector2(TILE - 1.0, TILE - 1.0))
		draw_rect(rect, TERRAIN_COLORS[cell.terrain])
		if cell.has_location():
			draw_circle(rect.get_center(), TILE * 0.22, Color(0.95, 0.85, 0.3))

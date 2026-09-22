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
## Demo interactiva de Terrain Forge: dropdown de topología (hex del anfitrión
## o cuadrados standalone), seed, falloff de isla y stats en vivo.
## El render de hexes se dibuja a mano (fórmulas odd-r pointy-top) para que
## el demo no dependa de los renderers del anfitrión.

const MAP_WIDTH := 26
const MAP_HEIGHT := 16
const HEX_SIZE := 17.0
const SQ_TILE := 22.0

const TERRAIN_COLORS := {
	MapCell.Terrain.WATER: Color(0.24, 0.44, 0.64),
	MapCell.Terrain.PLAINS: Color(0.56, 0.72, 0.40),
	MapCell.Terrain.FOREST: Color(0.28, 0.52, 0.30),
	MapCell.Terrain.MOUNTAIN: Color(0.58, 0.55, 0.50),
	MapCell.Terrain.ROAD: Color(0.76, 0.68, 0.46),
}

var use_hex := true
var seed_value := 42
var falloff := 0.35
var roads := true
var square_grid: SquareGrid
var hex_grid
var stats_label: Label


func _ready() -> void:
	_build_ui()
	_regenerate()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var topology_picker := OptionButton.new()
	topology_picker.add_item("Hex (host)")
	topology_picker.add_item("Squares (standalone)")
	topology_picker.item_selected.connect(func(index: int) -> void:
		use_hex = index == 0
		_regenerate())
	box.add_child(topology_picker)

	var seed_box := SpinBox.new()
	seed_box.min_value = 0
	seed_box.max_value = 999999
	seed_box.value = seed_value
	seed_box.value_changed.connect(func(value: float) -> void:
		seed_value = int(value)
		_regenerate())
	box.add_child(seed_box)

	var falloff_row := HBoxContainer.new()
	box.add_child(falloff_row)
	var falloff_slider := HSlider.new()
	falloff_slider.min_value = 0.0
	falloff_slider.max_value = 0.8
	falloff_slider.step = 0.05
	falloff_slider.value = falloff
	falloff_slider.custom_minimum_size = Vector2(180, 20)
	falloff_slider.value_changed.connect(func(value: float) -> void:
		falloff = value
		_regenerate())
	falloff_row.add_child(falloff_slider)

	var roads_check := CheckBox.new()
	roads_check.text = "Roads"
	roads_check.button_pressed = roads
	roads_check.toggled.connect(func(pressed: bool) -> void:
		roads = pressed
		_regenerate())
	box.add_child(roads_check)

	stats_label = Label.new()
	box.add_child(stats_label)


func _regenerate() -> void:
	var params := {
		"seed": seed_value,
		"island_falloff": falloff,
		"smoothing_passes": 1,
		"river_count": 3,
		"location_count": 4,
		"location_spacing": 2,
		"roads": roads,
	}
	square_grid = null
	hex_grid = null
	if use_hex and HexTopology.is_host_available():
		hex_grid = HexTopology.generate_hex(MAP_WIDTH, MAP_HEIGHT, params)
	else:
		square_grid = SquareGrid.new(MAP_WIDTH, MAP_HEIGHT)
		square_grid.generate_cells()
		TerrainForge.generate(SquareTopology.new(square_grid), params)
	_update_stats(params)
	queue_redraw()


func _update_stats(params: Dictionary) -> void:
	if hex_grid != null:
		stats_label.text = "hex %dx%d · seed %d · falloff %.2f" % [MAP_WIDTH, MAP_HEIGHT, seed_value, falloff]
	else:
		var stats: Dictionary = MapStats.distribution_report(SquareTopology.new(square_grid))
		stats_label.text = "squares %dx%d · seed %d · falloff %.2f · %s" % [
			MAP_WIDTH, MAP_HEIGHT, seed_value, falloff, str(stats.counts)]


func _draw() -> void:
	if hex_grid != null:
		_draw_hexes()
	elif square_grid != null:
		_draw_squares()


func _draw_squares() -> void:
	for coord in square_grid.get_all_cells():
		var cell: MapCell = square_grid.get_all_cells()[coord]
		var rect := Rect2(Vector2(coord) * SQ_TILE + Vector2(0, 120), Vector2(SQ_TILE - 1.0, SQ_TILE - 1.0))
		draw_rect(rect, TERRAIN_COLORS[cell.terrain])
		if cell.has_location():
			draw_circle(rect.get_center(), SQ_TILE * 0.22, Color(0.95, 0.85, 0.3))


func _draw_hexes() -> void:
	var origin := Vector2(0, 120)
	for coord in hex_grid.get_all_cells():
		var cell = hex_grid.get_all_cells()[coord]
		var center := origin + _hex_pixel(coord)
		draw_colored_polygon(_hex_polygon(center, HEX_SIZE * 0.94), TERRAIN_COLORS[cell.terrain])
		if cell.has_location():
			draw_circle(center, HEX_SIZE * 0.30, Color(0.95, 0.85, 0.3))


## Offset odd-r → pixel (pointy-top), mismo layout que el anfitrión.
func _hex_pixel(coord: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (coord.x + 0.5 * float(coord.y & 1))
	var y := HEX_SIZE * 1.5 * coord.y
	return Vector2(x, y)


func _hex_polygon(center: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := PI / 3.0 * i - PI / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * size)
	return points

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
## Demo interactiva de Terrain Forge: TODOS los params de generación expuestos
## en un panel lateral con secciones colapsables (ruido, isla, biomas,
## suavizado, ríos, locations, caminos, conectividad). Cada cambio regenera en
## vivo (26x16, <50ms). El dict miembro "params" es la única fuente de verdad.
## El render de hexes se dibuja a mano (fórmulas odd-r pointy-top) para que el
## demo no dependa de los renderers del anfitrión.

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

const TERRAIN_NAMES := {
	MapCell.Terrain.WATER: "Agua",
	MapCell.Terrain.PLAINS: "Llanura",
	MapCell.Terrain.FOREST: "Bosque",
	MapCell.Terrain.MOUNTAIN: "Montaña",
	MapCell.Terrain.ROAD: "Camino",
}

## Umbrales que cada preset de bioma sobrescribe (los demás quedan como están):
## refleja BiomeProfile.from_params — preset primero, key explícita pisa después.
const BIOME_PRESET_LEVELS := {
	"ladder": {"water_level": -0.2, "mountain_level": 0.4},
	"continent": {"water_level": -0.12, "mountain_level": 0.5},
	"archipelago": {"water_level": 0.02, "mountain_level": 0.3},
	"highlands": {"water_level": -0.35, "mountain_level": 0.25},
}

## Defaults del motor + gusto de la demo (falloff 0.35, smoothing 1, roads on).
## Excluidos (no representables en UI o sin efecto): classify_fn, road_cost_fn,
## stages, moisture_frequency (solo actúa con classify_fn).
const DEFAULT_PARAMS := {
	"seed": 42,
	"noise_type": FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
	"frequency": 0.08,
	"octaves": 5,
	"fractal_gain": 0.5,
	"lacunarity": 2.0,
	"fractal_type": FastNoiseLite.FRACTAL_FBM,
	"domain_warp": 0.0,
	"domain_warp_frequency": 0.05,
	"island_falloff": 0.35,
	"island_falloff_power": 2.0,
	"biome": "ladder",
	"water_level": -0.2,
	"forest_level": 0.1,
	"mountain_level": 0.4,
	"road_level": 0.0,
	"elevation_scale": 10.0,
	"smoothing_passes": 1,
	"river_count": 3,
	"river_spacing": 3,
	"river_length_min": 4,
	"river_length_max": 10,
	"river_downhill_bias": 0.0,
	"river_straightness": 0.0,
	"river_water": false,
	"river_width": 1,
	"location_count": 4,
	"location_type": 1,
	"location_spacing": 2,
	"location_terrain_filter": [],
	"roads": true,
	"road_terrain": true,
	"road_water_cost": 8.0,
	"road_mountain_cost": 0.0,
	"connectivity_mode": "report",
}

var params: Dictionary = DEFAULT_PARAMS.duplicate(true)
var use_hex := true
var square_grid: SquareGrid
var hex_grid
var stats_label: Label
var seed_spin: SpinBox
var last_report := {}
var _slider_meta := {}
var _spins := {}
var _terrain_filter_checks := {}


func _ready() -> void:
	_build_ui()
	_regenerate()


# --- UI ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(820, 12)
	panel.custom_minimum_size = Vector2(340, 0)
	layer.add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)

	var topology_picker := OptionButton.new()
	topology_picker.add_item("Hex (host)")
	topology_picker.add_item("Squares (standalone)")
	topology_picker.item_selected.connect(func(index: int) -> void:
		use_hex = index == 0
		_regenerate())
	root.add_child(topology_picker)

	var seed_row := HBoxContainer.new()
	root.add_child(seed_row)
	_add_row_label(seed_row, "Seed")
	seed_spin = SpinBox.new()
	seed_spin.min_value = 0
	seed_spin.max_value = 999999
	seed_spin.value = int(params["seed"])
	seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_spin.value_changed.connect(func(value: float) -> void:
		params["seed"] = int(value)
		_regenerate())
	seed_row.add_child(seed_spin)
	var bump_seed := Button.new()
	bump_seed.text = "+1"
	bump_seed.pressed.connect(_randomize_seed)
	seed_row.add_child(bump_seed)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(sections)
	_build_noise_section(sections)
	_build_island_section(sections)
	_build_biome_section(sections)
	_build_smoothing_section(sections)
	_build_river_section(sections)
	_build_location_section(sections)
	_build_road_section(sections)
	_build_connectivity_section(sections)

	stats_label = Label.new()
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.custom_minimum_size = Vector2(320, 0)
	root.add_child(stats_label)


func _build_noise_section(sections: Container) -> void:
	var box := _add_section(sections, "Ruido")
	_add_option_row(box, "noise_type", "Tipo",
		["Simplex", "Simplex Smooth", "Cellular", "Perlin", "Value Cubic", "Value"],
		[FastNoiseLite.TYPE_SIMPLEX, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.TYPE_CELLULAR,
			FastNoiseLite.TYPE_PERLIN, FastNoiseLite.TYPE_VALUE_CUBIC, FastNoiseLite.TYPE_VALUE])
	_add_slider_row(box, "frequency", "Frecuencia", 0.01, 0.5, 0.005, "%.3f")
	_add_spin_row(box, "octaves", "Octavas", 1, 8)
	_add_slider_row(box, "fractal_gain", "Gain", 0.0, 1.0, 0.05)
	_add_slider_row(box, "lacunarity", "Lacunaridad", 1.0, 4.0, 0.1)
	_add_option_row(box, "fractal_type", "Fractal",
		["None", "FBM", "Ridged", "Ping Pong"],
		[FastNoiseLite.FRACTAL_NONE, FastNoiseLite.FRACTAL_FBM, FastNoiseLite.FRACTAL_RIDGED, FastNoiseLite.FRACTAL_PING_PONG])
	_add_slider_row(box, "domain_warp", "Domain warp", 0.0, 2.0, 0.05)
	_add_slider_row(box, "domain_warp_frequency", "Warp frec.", 0.005, 0.2, 0.005, "%.3f")


func _build_island_section(sections: Container) -> void:
	var box := _add_section(sections, "Isla")
	_add_slider_row(box, "island_falloff", "Falloff", 0.0, 0.8, 0.05)
	_add_slider_row(box, "island_falloff_power", "Potencia", 0.5, 4.0, 0.1)


func _build_biome_section(sections: Container) -> void:
	var box := _add_section(sections, "Biomas")
	_add_option_row(box, "biome", "Preset base",
		["Ladder", "Continent", "Archipelago", "Highlands"],
		["ladder", "continent", "archipelago", "highlands"],
		_apply_biome_preset)
	_add_slider_row(box, "water_level", "Nivel agua", -0.6, 0.3, 0.01)
	_add_slider_row(box, "forest_level", "Nivel bosque", -0.2, 0.4, 0.01)
	_add_slider_row(box, "mountain_level", "Nivel montaña", 0.1, 0.8, 0.01)
	_add_slider_row(box, "road_level", "Nivel camino", -0.2, 0.3, 0.01)
	_add_slider_row(box, "elevation_scale", "Escala elev.", 1.0, 30.0, 0.5, "%.1f")


func _build_smoothing_section(sections: Container) -> void:
	var box := _add_section(sections, "Suavizado")
	_add_spin_row(box, "smoothing_passes", "Pasadas", 0, 5)


func _build_river_section(sections: Container) -> void:
	var box := _add_section(sections, "Ríos")
	_add_spin_row(box, "river_count", "Cantidad", 0, 12)
	_add_spin_row(box, "river_spacing", "Separación", 0, 8)
	_add_spin_row(box, "river_length_min", "Largo mín", 1, 20, func(value: int) -> void:
		# Guard: min > max invertiría randi_range del carver — subir el max.
		if int(params["river_length_max"]) < value:
			params["river_length_max"] = value
			_refresh_spin("river_length_max", value))
	_add_spin_row(box, "river_length_max", "Largo máx", 1, 40)
	_add_slider_row(box, "river_downhill_bias", "Sesgo descenso", 0.0, 1.0, 0.05)
	_add_slider_row(box, "river_straightness", "Rectitud", 0.0, 1.0, 0.05)
	_add_check_row(box, "Agua de verdad", bool(params["river_water"]), func(pressed: bool) -> void:
		params["river_water"] = pressed)
	_add_spin_row(box, "river_width", "Ancho", 1, 4)


func _build_location_section(sections: Container) -> void:
	var box := _add_section(sections, "Locations")
	_add_spin_row(box, "location_count", "Cantidad", 0, 20)
	_add_spin_row(box, "location_type", "Tipo", 0, 10)
	_add_spin_row(box, "location_spacing", "Separación", 0, 8)
	_add_terrain_filter_row(box)


func _build_road_section(sections: Container) -> void:
	var box := _add_section(sections, "Caminos")
	_add_check_row(box, "Generar caminos", bool(params["roads"]), func(pressed: bool) -> void:
		params["roads"] = pressed)
	_add_check_row(box, "Convertir terreno", bool(params["road_terrain"]), func(pressed: bool) -> void:
		params["road_terrain"] = pressed)
	_add_slider_row(box, "road_water_cost", "Costo agua", 0.0, 20.0, 0.5, "%.1f")
	_add_slider_row(box, "road_mountain_cost", "Costo montaña", 0.0, 20.0, 0.5, "%.1f")


func _build_connectivity_section(sections: Container) -> void:
	var box := _add_section(sections, "Conectividad")
	_add_option_row(box, "connectivity_mode", "Modo",
		["Report", "Repair"], ["report", "repair"])


# --- Helpers de fila: todos escriben params[key] y regeneran ---

func _add_section(parent: Container, title: String) -> VBoxContainer:
	var header := Button.new()
	header.text = "▾ " + title
	header.flat = true
	header.toggle_mode = true
	header.button_pressed = true
	parent.add_child(header)
	var content := VBoxContainer.new()
	parent.add_child(content)
	header.toggled.connect(func(open: bool) -> void:
		content.visible = open
		header.text = ("▾ " if open else "▸ ") + title)
	return content


func _add_row_label(row: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(118, 0)
	row.add_child(label)


func _add_slider_row(parent: Container, key: String, label: String,
		min_v: float, max_v: float, step: float,
		fmt: String = "%.2f", hook: Callable = Callable()) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_row_label(row, label)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(46, 0)
	value_label.text = fmt % float(params[key])
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = float(params[key])
	slider.custom_minimum_size = Vector2(150, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		params[key] = value
		value_label.text = fmt % value
		if hook.is_valid():
			hook.call(value)
		_regenerate())
	row.add_child(slider)
	row.add_child(value_label)
	_slider_meta[key] = {"slider": slider, "label": value_label, "fmt": fmt}


func _add_spin_row(parent: Container, key: String, label: String,
		min_v: int, max_v: int, hook: Callable = Callable()) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_row_label(row, label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = int(params[key])
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(value: float) -> void:
		params[key] = int(value)
		if hook.is_valid():
			hook.call(int(value))
		_regenerate())
	row.add_child(spin)
	_spins[key] = spin


func _add_check_row(parent: Container, label: String, initial: bool, on_toggle: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = label
	check.button_pressed = initial
	check.toggled.connect(func(pressed: bool) -> void:
		on_toggle.call(pressed)
		_regenerate())
	parent.add_child(check)
	return check


func _add_option_row(parent: Container, key: String, label: String,
		option_labels: Array, option_values: Array,
		hook: Callable = Callable()) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_row_label(row, label)
	var picker := OptionButton.new()
	for i in option_labels.size():
		picker.add_item(str(option_labels[i]))
		picker.set_item_metadata(i, option_values[i])
		if option_values[i] == params[key]:
			picker.select(i)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(index: int) -> void:
		params[key] = picker.get_item_metadata(index)
		if hook.is_valid():
			hook.call(params[key])
		_regenerate())
	row.add_child(picker)


func _add_terrain_filter_row(parent: Container) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_row_label(row, "Terrenos")
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var terrains: Array = [
		MapCell.Terrain.WATER, MapCell.Terrain.PLAINS, MapCell.Terrain.FOREST,
		MapCell.Terrain.MOUNTAIN, MapCell.Terrain.ROAD,
	]
	for terrain in terrains:
		var check := CheckBox.new()
		check.text = str(TERRAIN_NAMES[terrain])
		check.tooltip_text = "Sin tildes = acepta todas las celdas"
		check.toggled.connect(func(_pressed: bool) -> void:
			_rebuild_terrain_filter()
			_regenerate())
		_terrain_filter_checks[terrain] = check
		box.add_child(check)


func _refresh_slider(key: String, value: float) -> void:
	var meta: Dictionary = _slider_meta[key]
	meta["slider"].set_value_no_signal(value)
	meta["label"].text = str(meta["fmt"]) % value


func _refresh_spin(key: String, value: int) -> void:
	_spins[key].set_value_no_signal(value)


func _rebuild_terrain_filter() -> void:
	var filter: Array = []
	for terrain in _terrain_filter_checks:
		if _terrain_filter_checks[terrain].button_pressed:
			filter.append(terrain)
	params["location_terrain_filter"] = filter


func _apply_biome_preset(biome: Variant) -> void:
	var levels: Dictionary = BIOME_PRESET_LEVELS[str(biome)]
	for key in levels:
		params[key] = levels[key]
		_refresh_slider(key, levels[key])


## Seed secuencial (patrón de square_standalone): reproducible y sin tocar el
## RNG global de Godot (el test arquitectónico escanea examples/).
func _randomize_seed() -> void:
	params["seed"] = int(params["seed"]) % 999999 + 1
	seed_spin.set_value_no_signal(float(params["seed"]))
	_regenerate()


# --- Generación y stats ---

func _regenerate() -> void:
	last_report = {}
	square_grid = null
	hex_grid = null
	if use_hex and HexTopology.is_host_available():
		hex_grid = HexTopology.generate_hex(MAP_WIDTH, MAP_HEIGHT, params)
	else:
		square_grid = SquareGrid.new(MAP_WIDTH, MAP_HEIGHT)
		square_grid.generate_cells()
		last_report = TerrainForge.generate_with_report(SquareTopology.new(square_grid), params)
	_update_stats()
	queue_redraw()


func _update_stats() -> void:
	var topo: GridTopology
	if hex_grid != null:
		topo = HexTopology.new(hex_grid)
	else:
		topo = SquareTopology.new(square_grid)
	var stats: Dictionary = MapStats.distribution_report(topo)
	var connectivity: Dictionary = last_report.get("connectivity", ConnectivityChecker.analyze(topo))
	var regions: Array = connectivity.get("regions", [])
	var line2 := "regiones %d" % regions.size()
	if str(params["connectivity_mode"]) == "repair":
		line2 += " · reparadas %d" % int(connectivity.get("repaired", 0))
	if hex_grid != null:
		stats_label.text = "hex %dx%d · seed %d\n%s\n%s · puentes/ríos: solo squares" % [
			MAP_WIDTH, MAP_HEIGHT, int(params["seed"]), str(stats.counts), line2]
	else:
		stats_label.text = "squares %dx%d · seed %d\n%s\n%s · ríos %d · locations %d · puentes %d" % [
			MAP_WIDTH, MAP_HEIGHT, int(params["seed"]), str(stats.counts), line2,
			last_report.get("river_paths", []).size(),
			last_report.get("locations", []).size(),
			int(last_report.get("road_bridges", 0))]


# --- Render (sin cambios) ---

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

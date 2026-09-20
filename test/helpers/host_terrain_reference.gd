class_name HostTerrainReference
extends RefCounted
## Referencia congelada del algoritmo de terreno del generador del anfitrión
## (MapGenerator, módulo PRO → no vendorizable en un repo público).
##
## Replica EXACTAMENTE generate_noise_terrain() tal como está en
## hex-strategy-map v2.x (@40a8cab): FastNoiseLite SIMPLEX_SMOOTH a 0.08,
## sampling nx=x/w × 100, escalera de 5 bandas y elevación = val × 10.0.
## Los tests de paridad del forge comparan contra ESTA referencia — es el
## contrato de adopción publicado. Si el anfitrión cambia su generador, la
## paridad publicada sigue siendo esta (y se actualiza a conciencia).


const NOISE_SCALE := 100.0
const WATER_LEVEL := -0.2
const MOUNTAIN_LEVEL := 0.4
const FOREST_LEVEL := 0.1


static func generate(map_width: int, map_height: int, seed_value: int) -> HexGrid:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.08
	var grid := HexGrid.new(map_width, map_height)
	grid.generate_cells()
	for coord in grid.get_all_cells():
		var cell: HexCell = grid.get_cell(coord)
		var nx: float = float(coord.x) / float(map_width)
		var ny: float = float(coord.y) / float(map_height)
		var val: float = noise.get_noise_2d(nx * NOISE_SCALE, ny * NOISE_SCALE)
		cell.terrain = _ladder(val)
		cell.elevation = val * 10.0
	return grid


static func _ladder(val: float) -> int:
	if val < WATER_LEVEL:
		return HexCell.Terrain.WATER
	elif val > MOUNTAIN_LEVEL:
		return HexCell.Terrain.MOUNTAIN
	elif val > FOREST_LEVEL:
		return HexCell.Terrain.FOREST
	elif val > 0.0:
		return HexCell.Terrain.ROAD
	return HexCell.Terrain.PLAINS

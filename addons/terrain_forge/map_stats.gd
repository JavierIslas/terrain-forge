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

class_name MapStats
extends RefCounted
## Estadísticas del mapa para reportes y aserciones de tests.


## Diccionario terrain (int) → cantidad de celdas.
static func terrain_distribution(topology: GridTopology) -> Dictionary:
	var counts := {}
	for coord in topology.get_all_coords():
		var terrain: int = topology.get_terrain(coord)
		counts[terrain] = counts.get(terrain, 0) + 1
	return counts


## Distribución + proporciones + total; la suma de counts == cell_count.
static func distribution_report(topology: GridTopology) -> Dictionary:
	var counts := terrain_distribution(topology)
	var total := topology.cell_count()
	var ratios := {}
	for terrain in counts:
		ratios[terrain] = float(counts[terrain]) / float(total) if total > 0 else 0.0
	return {"cell_count": total, "counts": counts, "ratios": ratios}

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

class_name MapCell
extends RefCounted
## Modelo de celda standalone para topologías sin anfitrión.
##
## Los valores del enum Terrain están alineados valor por valor con el espacio
## int de terreno del anfitrión (ver docs/api_reference.md): la salida de
## generación alimenta palettes y tablas de costo del anfitrión sin capa de
## traducción. La alineación queda congelada por test arquitectónico.
## No incluye niebla: ese estado pertenece al anfitrión, no a la generación.

enum Terrain { ROAD, PLAINS, FOREST, MOUNTAIN, WATER }

var coord: Vector2i = Vector2i.ZERO
var terrain: int = Terrain.PLAINS
var elevation: float = 0.0
var location_type: int = 0
var location_data: Dictionary = {}
var tag: int = 0
var metadata: Dictionary = {}


func _init(cell_coord: Vector2i = Vector2i.ZERO, cell_terrain: int = Terrain.PLAINS) -> void:
	coord = cell_coord
	terrain = cell_terrain


## Retorna true si la celda tiene una location asignada (location_type > 0).
func has_location() -> bool:
	return location_type > 0


## Serializa la celda a un Dictionary compatible con JSON
## (claves espejo del modelo de celda del anfitrión, sin niebla).
func serialize() -> Dictionary:
	return {
		"coord": [coord.x, coord.y],
		"terrain": terrain,
		"location_type": location_type,
		"location_data": location_data,
		"tag": tag,
		"metadata": metadata,
		"elevation": elevation,
	}


static func _parse_coord(data: Dictionary) -> Vector2i:
	var raw = data.get("coord", [0, 0])
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO


## Reconstruye una MapCell desde un Dictionary generado por serialize().
static func deserialize(data: Dictionary) -> MapCell:
	var cell := MapCell.new(_parse_coord(data), int(data.get("terrain", Terrain.PLAINS)))
	cell.location_type = int(data.get("location_type", 0))
	cell.location_data = data.get("location_data", {})
	cell.tag = int(data.get("tag", 0))
	cell.metadata = data.get("metadata", {})
	cell.elevation = float(data.get("elevation", 0.0))
	return cell

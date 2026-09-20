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

class_name BiomeProfile
extends RefCounted
## Perfil de biomas: umbrales de la escalera de clasificación + amplitud de
## elevación + clasificador custom inyectable.
##
## create_ladder() congela la paridad con el generador del anfitrión; los
## presets ajustan la mezcla de terrenos sin tocar el mecanismo.

var water_level: float = -0.2
var forest_level: float = 0.1
var mountain_level: float = 0.4
var elevation_scale: float = 10.0
## Clasificador custom: (value: float, moisture: float) -> int (terreno).
## Si es válido, reemplaza la escalera de umbrales por completo.
var classify_fn: Callable = Callable()


## Escalera exacta del anfitrión (paridad bit a bit por test).
static func create_ladder() -> BiomeProfile:
	return BiomeProfile.new()


## Continentes grandes: menos agua, montañas escasas.
static func create_continent() -> BiomeProfile:
	var profile := BiomeProfile.new()
	profile.water_level = -0.12
	profile.mountain_level = 0.5
	return profile


## Archipiélago: abundante agua, tierra fragmentada.
static func create_archipelago() -> BiomeProfile:
	var profile := BiomeProfile.new()
	profile.water_level = 0.02
	profile.mountain_level = 0.3
	return profile


## Tierras altas: poca agua, mucho relieve.
static func create_highlands() -> BiomeProfile:
	var profile := BiomeProfile.new()
	profile.water_level = -0.35
	profile.mountain_level = 0.25
	return profile


## Lee el perfil desde params: "water_level", "forest_level",
## "mountain_level", "elevation_scale", "classify_fn", "biome" (String:
## "ladder" | "continent" | "archipelago" | "highlands"; default "ladder").
static func from_params(params: Dictionary) -> BiomeProfile:
	var profile := _preset(str(params.get("biome", "ladder")))
	profile.water_level = float(params.get("water_level", profile.water_level))
	profile.forest_level = float(params.get("forest_level", profile.forest_level))
	profile.mountain_level = float(params.get("mountain_level", profile.mountain_level))
	profile.elevation_scale = float(params.get("elevation_scale", profile.elevation_scale))
	profile.classify_fn = params.get("classify_fn", Callable())
	return profile


static func _preset(name: String) -> BiomeProfile:
	match name:
		"continent":
			return create_continent()
		"archipelago":
			return create_archipelago()
		"highlands":
			return create_highlands()
		"ladder":
			return create_ladder()
	push_error("BiomeProfile: preset desconocido '%s', se usa ladder" % name)
	return create_ladder()

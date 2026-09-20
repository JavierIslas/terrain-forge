# Terrain Forge — Getting Started

## Squares (standalone, no host required)

```gdscript
var grid := SquareGrid.new(40, 30)
grid.generate_cells()
var topology := SquareTopology.new(grid)          # 4-dir; SquareTopology.new(grid, 8) for 8-dir
TerrainForge.generate(topology, {"seed": 42, "octaves": 4, "smoothing_passes": 1,
	"river_count": 3, "location_count": 5, "location_spacing": 3})
# grid.cells now holds MapCells with terrain/elevation; grid.edges holds RIVER edges.
```

## Hex (requires hex_strategy_map — FREE tier is enough)

```gdscript
var grid = HexTopology.generate_hex(40, 30, {"seed": 42})
# grid IS a HexGrid: feed it to HexRenderer, FogOfWar, PathFinder, TurnManager —
# the whole host stack works unchanged.
```

**Adoption contract**: with default terrain params, the same `seed` produces
exactly the same terrain and elevation as the host's
`MapGenerator.generate_noise_terrain` (bit-for-bit, test-frozen). Migrating an
existing game only changes which function creates the grid. The parity is
pinned to the host algorithm as of hex-strategy-map v2.x (this repo keeps an
embedded reference; if the host generator ever changes, this contract is
updated deliberately, not by surprise).

## Improvements you couldn't get before

```gdscript
# Fractal detail + island shape + cleanup
TerrainForge.generate(topo, {"seed": 7, "octaves": 5, "domain_warp": 30.0,
	"island_falloff": 0.45, "smoothing_passes": 2})

# Presets
var params: Dictionary = TerrainForge.preset("archipelago")
params.seed = 7
TerrainForge.generate(topo, params)

# Guarantee a connected landmass
TerrainForge.generate(topo, {"seed": 7, "connectivity_mode": "repair"})

# Biome rules via classify_fn (elevation × moisture)
TerrainForge.generate(topo, {"seed": 7,
	"classify_fn": func(value: float, moisture: float) -> int:
		if value < -0.2: return MapCell.Terrain.WATER
		if moisture > 0.25: return MapCell.Terrain.FOREST
		return MapCell.Terrain.PLAINS})
```

## Custom topology

```gdscript
class_name TriangleTopology extends GridTopology
# Override get_neighbors/is_valid/distance/line + storage; the engine,
# rivers, smoothing, connectivity and locations work unchanged.
```

## Custom pipeline stage

```gdscript
var mark_capitals := func(topology: GridTopology, ctx: Dictionary) -> void:
	var rng: SeededRng = ctx.master.derive_stream(0xCAF)
	# ... read ctx.heights, write via topology.set_location ...
TerrainForge.generate(topo, {"seed": 7,
	"stages": [TerrainForge.STAGE_ELEVATION, TerrainForge.STAGE_CLASSIFY, mark_capitals]})
```

## Saved maps: regenerate or re-materialize

```gdscript
var report := TerrainForge.generate_with_report(topo, {"seed": 42})
# Re-materialize the exact same state later, on any topology:
TerrainForge.apply_snapshot(other_topology, report.snapshot)
# Or regenerate terrain on an existing host grid (e.g. restored from save):
HexTopology.apply(loaded_hex_grid, {"seed": 42, "island_falloff": 0.3})
```

## Where to look next

- `docs/api_reference.md` — full params table and port contract.
- `examples/forge_demo/` — interactive demo with a hex/square dropdown.
- `examples/square_standalone/` — squares with zero host dependencies.

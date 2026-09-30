# Terrain Forge — API Reference

Procedural terrain generation with pluggable grid topology. Generate on
**hex** (via `hex_strategy_map`), on **squares** (built-in, no host needed),
or on **any topology you implement** by extending `GridTopology`.

## Dependency policy

- **Core is host-free**: every module except `hex_topology.gd` has zero
  references to `hex_strategy_map`. Squares work with this addon alone
  (enforced by `test_forge_architecture.gd` on every run).
- **Hex mode** requires only the **FREE tier** of `hex_strategy_map`
  (`hex_grid.gd` + `hex_cell.gd`); it never touches the host's PRO modules.
- `HexTopology` resolves the host scripts with `load()` after
  `is_host_available()`, so projects without the host still parse the addon.

## Determinism

All randomness flows through `SeededRng` (local `RandomNumberGenerator` +
splitmix64 stream derivation). Nothing consumes Godot's global RNG — a
regression test (`test_*_ignora_el_rng_global`) runs the full pipeline and
asserts the global sequence is untouched.

- `params["seed"]` (default `0`) is the **master seed**. Negative seeds are
  valid and deterministic (the host generator accepts them too).
- The **elevation stage uses the master seed directly**, so terrain output is
  **bit-for-bit identical** to `MapGenerator.generate_noise_terrain` for the
  same seed (frozen by test, all 5 ladder bands included, negative seeds too).
- **Regeneration semantics**: the `rivers` and `locations` stages clear the
  previous `RIVER` edges and locations before writing the new ones, so
  regenerating (via `HexTopology.apply` or a second `generate` over the same
  topology) with the same seed reproduces the exact same final state — no
  accumulation, no orphan rivers. The `roads` stage (only when `"roads":
  true`) likewise clears previous `ROAD` edges before carving. Edges of
  other types (ROAD/WALL placed by your game) are preserved as long as the
  roads stage doesn't run; `apply_snapshot` re-materializes the full state
  including the snapshot's `ROAD` edges.
- Rivers/locations derive independent streams (`SALT_RIVERS = 7919`,
  `SALT_LOCATIONS = 104729` — the host's offsets). They are deterministic
  but intentionally **not** identical to the host's rivers (better starts:
  high elevation + spacing; optional downhill bias). Roads use **no rng at
  all**: the MST + Dijkstra trace is a pure function of (terrain, locations,
  params) with `(cost, x, y)` tie-breaking.

## TerrainForge (engine, static)

```gdscript
static func generate(topology: GridTopology, params: Dictionary = {}) -> GridTopology
static func generate_with_report(topology: GridTopology, params: Dictionary = {}) -> Dictionary
static func apply_snapshot(topology: GridTopology, snapshot: Dictionary) -> void
static func preset(name: String) -> Dictionary  # "pangaea" | "archipelago" | "highlands"
static func apply_falloff(heights: PackedFloat32Array, w: int, h: int, strength: float, power: float = 2.0) -> PackedFloat32Array
```

`report` contains: `seed`, `stages_run`, `stats` (`{cell_count, counts,
ratios}`), `snapshot` (re-materializable state), `river_paths`, `locations`,
`location_type`, `road_paths`, `road_bridges`, `connectivity`.

### Stages

`params["stages"]` accepts an `Array` mixing built-in names and custom
`Callable`s `(topology, ctx) -> void`. Default pipeline:

```
elevation → moisture → falloff → classify → smooth → rivers → locations → roads → connectivity
```

### Params (all optional)

| Key | Default | Effect |
|---|---|---|
| `seed` | `0` | Master seed (terrain parity with the host) |
| `noise_type`, `frequency` | `SIMPLEX_SMOOTH`, `0.08` | FastNoiseLite sampling |
| `octaves`, `fractal_gain`, `lacunarity` | `5`, `0.5`, `2.0` | fBm (host's implicit defaults) |
| `fractal_type` | `FRACTAL_FBM` | `FRACTAL_RIDGED` for mountain chains, `FRACTAL_PING_PONG` for twisted terrain (explicit FBM = host parity) |
| `domain_warp`, `domain_warp_frequency` | `0.0`, `0.05` | Amplitude > 0 enables native warp |
| `island_falloff`, `island_falloff_power` | `0.0`, `2.0` | Radial falloff pushing edges to water |
| `biome` | `"ladder"` | `"continent"` / `"archipelago"` / `"highlands"` |
| `water_level`, `forest_level`, `mountain_level`, `elevation_scale` | `-0.2`, `0.1`, `0.4`, `10.0` | Ladder thresholds (host parity) |
| `road_level` | `0.0` | ROAD band lower threshold (0.0 = host literal; raise it to shrink the band) |
| `classify_fn` | — | `(value: float, moisture: float) -> int`, replaces the ladder |
| `moisture_frequency` | `0.05` | Moisture noise (sampled when `classify_fn` is set) |
| `smoothing_passes` | `0` | Majority-vote smoothing passes |
| `river_count`, `river_spacing` | `3`, `3` | Rivers: count and min distance between starts |
| `river_length_min`, `river_length_max` | `4`, `10` | Walk length in steps |
| `river_downhill_bias`, `river_straightness` | `0.0`, `0.0` | Walk scoring bonuses |
| `river_water` | `false` | Convert the river bed to WATER terrain (RIVER edges stay on the center line) |
| `river_width` | `1` | Water rings around the bed (clamped to >= 1) |
| `location_count`, `location_type` | `0`, `1` | Locations to place |
| `location_terrain_filter` | `[]` | Empty accepts every cell (incl. water) |
| `location_spacing` | `0` | Min topological distance between locations |
| `roads` | `false` | Gate: connect all locations via MST + cost-aware trace |
| `road_terrain` | `true` | Convert path terrain to ROAD (bridges stay WATER) |
| `road_water_cost` | `8.0` | Extra cost to enter WATER (bridges allowed, not blocked) |
| `road_mountain_cost` | `0.0` | Extra cost to enter MOUNTAIN (0 = cross freely) |
| `road_cost_fn` | — | `(coord) -> float`, replaces both penalties |
| `connectivity_mode` | `"report"` | `"repair"` carves WATER→PLAINS corridors |

## GridTopology (port)

Extend it to support any topology. Override the ~16 required virtuals:
geometry (`get_neighbors` — candidates **unfiltered**, `is_valid`, `distance`,
`line` — may include **out-of-grid** cells between valid endpoints; consumers
filter with `is_valid`, like `get_neighbors`), iteration (`get_all_coords`
row-major, `get_dimensions`, `cell_count`), storage (`get/set_terrain`,
`get/set_elevation`, `set_location`, `has_location`, `set_edge`,
`edge_count`). Defaults `push_error` and return neutral values.

Three **optional** cost virtuals default to neutral semantics, so a topology
without a cost model searches with uniform costs: `get_movement_cost` (1.0),
`is_passable` (= `is_valid`), `get_edge_cost` (0.0). The built-ins override
them to mirror the host's cost resolution (`SquareGrid` cost tables; host
grid methods, including its A* heuristic cache).

## Built-in topologies

- **`SquareTopology`** (host-free): wraps `SquareGrid`; connectivity 4
  (Manhattan + staircase line) or 8 (Chebyshev + Bresenham).
- **`HexTopology`** (requires host FREE):
  ```gdscript
  static func is_host_available() -> bool
  static func generate_hex(map_width: int, map_height: int, params: Dictionary = {})  # -> HexGrid
  static func apply(host_grid, params: Dictionary = {}) -> void  # regenerate on an existing HexGrid
  ```
  Writes through the host's public API (`set_terrain` keeps its A* heuristic
  cache correct).

## GridSearch (search, static)

Generic search over **any** topology — the same calls work on
`SquareTopology`, `HexTopology` and custom ports:

```gdscript
static func find_reachable(topology, origin: Vector2i, max_cost: float, params: Dictionary = {}) -> Dictionary
static func find_path(topology, origin: Vector2i, target: Vector2i, params: Dictionary = {}) -> Array[Vector2i]
static func find_path_astar(topology, origin: Vector2i, target: Vector2i, params: Dictionary = {}) -> Array[Vector2i]
```

- `find_reachable` → `Dictionary[Vector2i, float]`: every cell reachable
  within the movement budget (origin at 0.0; cells costing exactly the
  budget are included). The tactical movement-range primitive.
- `find_path` / `find_path_astar` → optimal path with **both endpoints
  included** (unlike the host's searcher, which omits the origin); `[]` if
  unreachable. `find_path_astar` scales `topology.distance` by the cheapest
  passable terrain cost (faster on large maps; `find_path` is the optimal
  reference).
- Step cost mirrors the host: `get_movement_cost(target) +
  get_edge_cost(origin, target)` — river edges (+2.0) make crossing
  expensive, road edges (−0.5) make it cheap; impassability is terrain-only
  (WATER −1.0). Deterministic by construction (total-order heap
  `(cost, x, y)`); read-only over the topology, so regenerating the map
  between calls is safe.
- `params`: `"cost_fn"` `(from, to) -> float` (replaces the additive model),
  `"passable_fn"` `(coord) -> bool` (replaces `is_passable`; also governs
  target validation — the bridge pattern for water-crossing roads),
  `"reachable"` (restricts `find_path` to a set from `find_reachable`,
  replacing the passability filter).
- Frozen by parity test: on hex, `find_reachable` costs match the host's
  searcher key-for-key and `find_path` matches its optimal cost.

## Pathfinding: why not AStarGrid2D / NavigationServer2D?

Godot's `AStarGrid2D` is a good fit for **games** that only need
point-to-point paths on a rectangular square grid. If that's your case:

```gdscript
var astar := AStarGrid2D.new()
astar.region = Rect2i(0, 0, grid.width, grid.height)
astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER  # von Neumann; ALWAYS for Moore
astar.update()  # clears solids/weights: (re)apply them after every update()
for coord in grid.get_all_cells():
	if grid.is_passable(coord):
		astar.set_point_weight_scale(coord, grid.get_movement_cost(coord))
	else:
		astar.set_point_solid(coord)
var path: Array[Vector2i] = astar.get_id_path(from_coord, to_coord)
```

Keep `jumping_enabled = false` (it ignores weight scales). What it cannot
express — and `GridSearch` can: per-**edge** costs (rivers/roads between
cells), `find_reachable` movement ranges, non-rectangular topologies and
hex. `NavigationServer2D` / `TileSet` navigation layers are polygon navmesh
for continuous agents — the wrong model for cell-by-cell turns (float
waypoints, region-level costs only).

## Enum alignment (frozen by test)

`MapCell.Terrain` and `SquareGrid.EdgeType` mirror the host's
`HexCell.Terrain` / `HexGrid.EdgeType` value-for-value (ROAD=0 … WATER=4;
RIVER=1 …). Forged hex output feeds host palettes/cost tables with no
translation layer.

## Snapshot

`report.snapshot` = `{seed, width, height, heights, terrain_classes,
elevation_scale, river_paths, road_paths, locations, location_type}` — final
state (post-smoothing). `TerrainForge.apply_snapshot()` re-materializes it on
any topology with the same dimensions (hex or squares): same snapshot → same
map. Snapshots without `road_paths` (older versions) still apply.

Persistence: binary-safe, not JSON-round-trip-safe. `var_to_bytes` /
`bytes_to_var` preserve every type exactly; `JSON.parse_string` returns the
`Vector2i` values in `river_paths`, `road_paths` and `locations` as plain
`Array`s, which `apply_snapshot` rejects. For JSON saves use
`SquareGrid.serialize()` / `deserialize()` (whole grid, squares standalone).

## Out of scope (v1 roadmap)

Fog of war, renderers and turn management belong to the host stack (hex) or
to your game (squares). Square pathfinding shipped as `GridSearch` (see
above).

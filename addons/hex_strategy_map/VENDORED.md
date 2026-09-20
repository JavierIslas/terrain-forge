# Vendored test fixture — hex_strategy_map (subset)

These four scripts are vendored from the
[hex-strategy-map](https://github.com/JavierIslas/hex-strategy-map) addon
(MIT, © 2026 Javier Islas), pinned at commit `40a8cab`:

- `hex_grid.gd` — offset/cube coordinates, neighbors, distances, terrain costs
- `hex_cell.gd` — cell model (terrain, elevation, fog state)
- `fog_state.gd` — `FogState` enum (dependency of `hex_cell.gd`)
- `path_finder.gd` — Dijkstra + A* (dependency of `HexGrid.find_reachable`)

**Why they exist here:** Terrain Forge's test suite (and the `HexTopology`
adapter's host probe, which checks for `res://addons/hex_strategy_map/hex_grid.gd`)
needs the host's FREE-tier classes at that exact path. `map_generator.gd` is
intentionally NOT vendored — it is a paid PRO module of the host — so terrain
parity is frozen against an embedded reference instead: see
`test/helpers/host_terrain_reference.gd`.

**For production hex maps** install the real addon (the FREE tier is enough):
Godot Asset Library → *Hex Strategy Map*. To refresh this fixture, copy the
four files again from the upstream repo, update the pin above, and re-run the
test suite.

**Drift watch:** a scheduled CI job (`.github/workflows/drift.yml`, weekly)
compares these four files against the published host
(`JavierIslas/hex-strategy-map-free@main`). If they drift, the job fails and
opens an issue — the parity/compat contracts must be re-verified against the
new host before the pin is moved.

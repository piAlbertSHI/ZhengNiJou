# Direction / Inventory Evidence Boundary

This is a stage-summary salvage and a read-only native inventory comparison,
not a successfully exported paired trajectory or a new simulation result.

- Historical physical producer: b5a288a. Natural process exit: 1.
- Current reader / durability repair producer: 35e9484.
- Two calculations completed 20 s each; a one-shot JSON filename collision
  happened before the aggregate raw NPZ could be saved. Full profiles are lost.
- Copied failure/stage/flow files were compared by SHA-256 to the originals.
- Reported local residuals were computed in memory; they cannot be re-audited
  from absent raw profiles. First-half cross-arm array checking never ran.
- retained_stage_comparison.json is authoritative over the preliminary r1
  reader output. The preliminary reader source was not committed at execution;
  r2 binds to the committed current reader without rerunning physics.
- Inventory evidence is conditional on the single-bed porosity contract and
  the retained native cold snapshot. It is not a new C200 inventory inspection.
- The 303.15 K excess fluid heat capacity is a reference proxy, not an
  integrated variable-density energy measurement.
- Distinct physical arms are not duplicates. No deletion was performed.
- Raw native observations stay at their existing single source location;
  no MAT, OP, full checkpoint or large trajectory is copied here.
- No restart, seed, periodic, full mechanism, hydraulic or Table4 authority.

Next structural diagnostic: one persistent SMA bed-fluid inventory switched
between hot/cold routes, preserving physical geometry, solid coordinates,
local energy/mass ledgers and all boundary histories. Do not halve volumes
silently, reset fluid at switches, or attach old Operating Points to new topology.

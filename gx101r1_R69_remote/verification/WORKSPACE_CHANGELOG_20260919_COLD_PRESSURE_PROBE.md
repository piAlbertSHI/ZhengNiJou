# 2026-09-19 Independent cold pressure-probe integration

## Change

`Run_HeatDriveECC_ColdChamberDiagnostic.m` now calls the existing
`Instrument_HeatDriveECC_PumpPressureProbes.m` after each in-memory diagnostic
model is configured and before the Simulink update/simulation. The
instrumentation adds named A/B pressure sensors to all three TL Pressure
Source blocks (SMA, SE stage 2, and SE stage 4) and never saves the model.

Each arm now retains:

- `pump_pressure_probe_contract.json`, with six probe definitions and the
  simulation status;
- `pressure_probe_signals` in `observations.mat`;
- the probe signal names and count in `cold_chamber_execution.json`.

The existing independent cold-start restrictions are unchanged: no C200 state
import, no checkpoint, no production recovery, and no Table 4 claim. This
change only closes the previously missing independent pressure A/B observation
boundary needed for the next cold-seed audit.

## Verification boundary

The runner must be executed from a clean committed diagnostic worktree because
its source-contract guard rejects tracked modifications. The unresolved main
worktree SLX change remains isolated and is not part of this diagnostic.

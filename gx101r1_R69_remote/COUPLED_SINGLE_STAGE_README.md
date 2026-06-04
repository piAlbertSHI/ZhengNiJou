# Coupled Single-Stage SMA Runner

## Entry Points

Run one coupled cycle:

```matlab
cd('C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote');
options = Build_CoupledSMA_Default_Options();
options.n_cycles = 1;
options.outputs_dir = fullfile(pwd, 'outputs_coupled_single_case');
result = Run_CoupledSMA_SingleStage_Cycles(options);
```

Run the smoke validation:

```matlab
cd('C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote');
summary = Validate_CoupledSMA_SingleStage_Smoke();
```

The smoke output is written to:

```text
gx101r1_R69_remote/outputs_coupled_single_smoke
```

## Stage Flow

1. `actuator_heat_load`: MATLAB-layer lumped actuator heats, transforms from high `xi` toward low `xi`, and generates the pressure profile passed to `Run_GlobalXi_Time_Loading_Prototype`.
2. `hold_exchange`: default runner calls the existing `Run_Simulink_Exchange_Hook`; smoke validation uses explicit `surrogate_temperature_v1` because the local baseline Simulink run exceeded 10 minutes at stage 2.
3. `actuator_cool_unload`: actuator cools, `xi` returns high, pressure drops to zero, and the profile is passed to `Run_GlobalXi_Unloading_Prototype`.
4. `cooldown_exchange`: same exchange/writeback/restart-balance interface as the original runner.

## Implementation Notes

- `Run_GlobalXi_Simulink_Cycles.m` is not modified.
- `GlobalXi_TimeStep_Core.m` is only extended to accept optional `pressure_time_s` plus `pressure_Pa` or `pressure_MPa`. If these fields are absent, the original `Pmax` pressure law is unchanged.
- No Simulink model file is modified.
- The first coupling solver uses a quasi-static linear compliance proxy:

```text
F = k_a * (delta_free - transmission_ratio * delta_r)
F = P * A_effective
delta_r = compliance * P
```

This is intended as an auditable first version, not a final calibrated material model.

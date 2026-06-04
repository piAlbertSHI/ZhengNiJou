# Agent2 Baseline Notes

## Context Read

Agent2 first read the required project task and design notes:

- `Agent2的任务书.txt`
- `现有程序阅读与正逆耦合改造构思.md`
- `SMA热驱动正逆耦合文献阅读要点.md`

The interpreted data flow is:

1. Existing mature flow keeps `Run_GlobalXi_Simulink_Cycles.m` as the external-pressure runner.
2. Stage 1/3 call `Run_GlobalXi_Time_Loading_Prototype.m` and `Run_GlobalXi_Unloading_Prototype.m`, which delegate to `GlobalXi_TimeStep_Core.m`.
3. The refrigerant state is `Y = [u, w, T, xi]`; checkpoints preserve `Y`, material state, grid, params, pressure and work audit metrics.
4. Stage 2/4 call `Run_Simulink_Exchange_Hook.m`; the Simulink path only updates the 51-node temperature field.
5. Temperature writeback uses `Build_GlobalXi_Checkpoint_From_Exchanged_T.m`; mechanics and phase consistency are restored by `Build_GlobalXi_Restart_Balance_Checkpoint.m`.
6. Coupled SMA work should add a MATLAB-layer actuator and coupling solver while preserving the original external-pressure runner.

## Baseline Run

Baseline command shape:

```matlab
cd('C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote');
opts = struct();
opts.nCycles = 1;
opts.run_label = 'agent2_baseline';
opts.outputs_dir = fullfile(pwd, 'outputs_agent2_baseline');
opts.save_checkpoints = true;
opts.save_plots = false;
opts.store_raw_simout = false;
opts.batch_light_mode = true;
opts.solver_options = struct( ...
    'Nt', 60, ...
    'Nt_unload', 90, ...
    'T_load', 0.03, ...
    'T_unload', 0.03, ...
    'enable_unload_retry', false, ...
    'skip_loading_jv_audit', true, ...
    'store_work_history', true);
opts.exchange_options = struct( ...
    'hotflush_stop_time_s', 0.05, ...
    'coldflush_stop_time_s', 0.05, ...
    'simulation_mode', 'normal', ...
    'allow_simulation_mode_fallback_to_normal', true, ...
    'probe_sample_count', 20, ...
    'flush_volume_target_ratio', 0.5, ...
    'allow_flush_volume_ratio_out_of_gate', true, ...
    'actual_flush_pressure_control_enable_for_target_duty', false, ...
    'actual_flush_pressure_max_attempts', 1, ...
    'actual_flush_pressure_compensation_enabled', false, ...
    'simulink_solver_max_step', 0.01);
run_result = Run_GlobalXi_Simulink_Cycles(opts);
```

Result on 2026-06-04:

- MATLAB R2025b was available.
- The original external-pressure runner entered the main flow.
- Stage 1 loading completed and wrote `outputs_agent2_baseline/checkpoints/cycle001_load_end.mat`.
- The process did not return within 10 minutes while proceeding into the stage 2 Simulink path, so the baseline run was stopped manually.
- Generated outputs remain untracked and must not be committed.

This is sufficient to confirm the external-pressure path is still present and stage 1 is operational before Agent2 changes. Later coupled smoke validation may use the non-Simulink `directional_101` backend for fast CI-style checks, while preserving the Simulink-compatible exchange interface.

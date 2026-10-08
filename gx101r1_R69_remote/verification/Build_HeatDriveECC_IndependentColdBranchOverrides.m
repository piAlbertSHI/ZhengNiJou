function overrides = Build_HeatDriveECC_IndependentColdBranchOverrides(config)
% Shared projection binds restore-preflight inputs to actual warmup controller settings.
    overrides = struct();
    overrides.se_stage2_pressure_pi_kp_MPa_per_kgps = config.stage2_kp;
    overrides.se_stage2_pressure_pi_initial_kp_MPa_per_kgps = config.stage2_initial_kp;
    overrides.se_stage2_pressure_pi_transition_start_s = 0;
    overrides.se_stage2_pressure_pi_transition_duration_s = 0;
    overrides.se_stage4_pressure_pi_kp_MPa_per_kgps = config.stage4_kp;
    overrides.se_stage4_pressure_pi_initial_kp_MPa_per_kgps = config.stage4_initial_kp;
    overrides.se_stage4_pressure_pi_ki_MPa_per_kgps_s = config.stage4_ki;
    overrides.se_stage4_pressure_pi_transition_start_s = 0;
    overrides.se_stage4_pressure_pi_transition_duration_s = config.stage4_transition_duration_s;
    overrides.se_stage4_endpoint_viscosity_blend_initial = config.stage4_endpoint_viscosity_blend_initial;
    overrides.se_stage4_endpoint_viscosity_blend_final = config.stage4_endpoint_viscosity_blend_final;
    overrides.se_stage4_endpoint_viscosity_blend_start_s = 0;
    overrides.se_stage4_endpoint_viscosity_blend_duration_s = 0;
    overrides.se_stage4_endpoint_viscosity_blend_periodic = config.stage4_endpoint_viscosity_blend_periodic;
    overrides.se_stage4_endpoint_viscosity_closure_mode = char(config.stage4_endpoint_viscosity_closure_mode);
    overrides.se_stage4_commutation_precharge_fraction = config.stage4_commutation_precharge_fraction;
    overrides.pressure_pi_error_filter_tau_s = config.pressure_pi_error_filter_tau_s;
    overrides.se_stage4_pressure_bias_trim_MPa = config.stage4_pressure_bias_trim_MPa;
    overrides.se_distributed_pressure_feedforward_diagnostic = config.distributed_pressure_feedforward_diagnostic;
    if isfield(config,'stage4_pressure_p_activity_mode')
        overrides.se_stage4_pressure_p_activity_mode = char(config.stage4_pressure_p_activity_mode);
    end
end

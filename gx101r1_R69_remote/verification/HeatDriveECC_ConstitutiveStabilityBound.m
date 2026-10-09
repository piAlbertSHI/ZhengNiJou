function record = HeatDriveECC_ConstitutiveStabilityBound(options, stage_id, dt_s)
% A phase-Jacobian infinity-norm bound from the actual compatibility and gate law.
    g=options.geometry;a=options.material.SMA;r=options.material.SE;c=options.constitutive;
    ratio=g.S_r_m2/g.S_a_m2;
    denominator=g.L_a_m*ratio/a.E_m_Pa+g.L_r_m/r.E_m_Pa;
    coupling=g.L_a_m*a.epsilon_T/denominator+g.L_r_m*r.epsilon_T/denominator;
    assert(denominator>eps && all([a.T_As_K-a.T_Ms_K,r.T_As_K-r.T_Ms_K]>0) && ...
        strcmp(c.integration_scheme,'bogacki_shampine_ode3') && c.phase_front_smoothing_1_per_s==0, ...
        'Bound requires the unchanged declared local phase law, without smoothing.');
    if any(stage_id==[1,2])
        rateA=c.rate_a_to_A_1_per_s;rateR=c.rate_r_load_1_per_s;
        slopeA=a.C_A_Pa_per_K;slopeR=r.C_M_Pa_per_K;
    else
        assert(any(stage_id==[3,4]),'Invalid thermal half-cycle.');
        rateA=c.rate_a_to_M_1_per_s;rateR=c.rate_r_stage3_unload_1_per_s;
        slopeA=a.C_M_Pa_per_K;slopeR=r.C_A_Pa_per_K;
    end
    % 0 <= gate <= 1 and gate' <= 1/width; phase and remaining fraction <= 1.
    boundA=rateA*(1+(slopeA*(a.T_As_K-a.T_Ms_K)+ratio*coupling)/max(c.drive_width_a_Pa,1));
    boundR=rateR*(1+(slopeR*(r.T_As_K-r.T_Ms_K)+coupling)/max(c.drive_width_r_Pa,1));
    bound=max(boundA,boundR);
    assert(isfinite(bound) && bound>=0 && isfinite(dt_s) && dt_s>=0, 'Invalid dimensional bound.');
    n=2^ceil(log2(max(1,dt_s*bound)));
    assert(n<=1024,'A new parameter domain needs a new numerical cost/accuracy qualification.');
    record=struct('phase_jacobian_norm_bound_per_s',bound,'SMA_bound_per_s',boundA, ...
        'SE_bound_per_s',boundR,'outer_sample_time_s',dt_s,'substeps',n, ...
        'internal_step_s',dt_s/n,'internal_step_times_bound',dt_s*bound/n, ...
        'bound_valid_for_phase_domain',[0,1], ...
        'scope','Phase subsystem at held input temperatures; not full Simscape stability or coupled convergence.');
end

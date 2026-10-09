function [state, audit, numerical] = Integrate_HeatDriveECC_StableConstitutiveSample(state, options, dt_s, stage_id)
% Offline numerical prototype: retain outer clock, integrate substep heat/work consistently.
    numerical=HeatDriveECC_ConstitutiveStabilityBound(options,stage_id,dt_s);
    initialA=state.xM_a_21;initialR=state.xM_r_21;
    assert(all([initialA(:);initialR(:)]>=0) && all([initialA(:);initialR(:)]<=1), 'Invalid initial phase.');
    if dt_s==0
        [state,audit]=HeatDriveECC_ConstitutiveCompatibilityStep51(state,options,dt_s,stage_id);
        return;
    end
    fixed_substeps = isfield(options.constitutive, 'diagnostic_substeps') && ...
        ~isempty(options.constitutive.diagnostic_substeps);
    if fixed_substeps
        n=options.constitutive.diagnostic_substeps;
        assert(n==round(n) && n>=1 && n<=1024, 'Invalid fixed diagnostic substeps.');
        [state,audit]=integrate_count(state,options,dt_s,stage_id,n);
        numerical.base_stability_substeps=numerical.substeps;
        numerical.substeps=n;numerical.internal_step_s=dt_s/n;
        numerical.internal_step_times_bound=numerical.internal_step_s*numerical.phase_jacobian_norm_bound_per_s;
        numerical.fixed_substeps=true;
        numerical.last_refinement_difference=NaN;
        numerical.refinement_levels=n;
        return;
    end
    n=numerical.substeps;initial=state;
    [coarse,~]=integrate_count(initial,options,dt_s,stage_id,n);
    local_target=1e-6;levels=n;
    while true
        assert(2*n<=2048,'No local convergence within the declared prototype cost bound.');
        [fine,fine_audit]=integrate_count(initial,options,dt_s,stage_id,2*n);
        difference=max(abs([fine.xM_a_21;fine.xM_r_21]-[coarse.xM_a_21;coarse.xM_r_21]));
        levels(end+1)=2*n; %#ok<AGROW>
        if difference<=local_target,break;end
        coarse=fine;n=2*n;
    end
    state=fine;audit=fine_audit;
    numerical.base_stability_substeps=numerical.substeps;
    numerical.substeps=2*n;numerical.internal_step_s=dt_s/(2*n);
    numerical.internal_step_times_bound=numerical.internal_step_s*numerical.phase_jacobian_norm_bound_per_s;
    numerical.local_phase_accuracy_target=local_target;numerical.last_refinement_difference=difference;
    numerical.refinement_levels=levels;
    numerical.fixed_substeps=false;
end

function [state,audit] = integrate_count(state,options,dt_s,stage_id,n)
    initialA=state.xM_a_21;initialR=state.xM_r_21;
    fields={'latentA','latentR','mechanicalA','mechanicalR','stressWorkR','phaseWorkR'};
    energy=zeros(options.node_count,numel(fields));
    for sub=1:n
        [state,audit]=HeatDriveECC_ConstitutiveCompatibilityStep51(state,options, ...
            dt_s/n,stage_id);
        for k=1:numel(fields),energy(:,k)=energy(:,k)+audit.([fields{k} '_J_21']);end
    end
    for k=1:numel(fields)
        audit.([fields{k} '_J_21'])=energy(:,k);
        audit.([fields{k} '_W_21'])=energy(:,k)/dt_s;
        audit.([fields{k} '_J_51'])=energy(:,k);
        audit.([fields{k} '_W_51'])=energy(:,k)/dt_s;
        audit.([fields{k} '_W'])=sum(energy(:,k))/dt_s;
    end
    audit.delta_xM_a_mean=mean(state.xM_a_21-initialA);
    audit.delta_xM_r_mean=mean(state.xM_r_21-initialR);
end

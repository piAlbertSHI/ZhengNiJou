function contract=Configure_HeatDriveECC_NativeConsistencyProbe(model,profile)
% Numerical-only diagnostic. Never change step, material, IC targets or PI.
    assert(ismember(profile,{'inherited','local_tight'}));
    paths=find_system(model,'LookUnderMasks','all','FollowLinks','on','MaskType','Solver Configuration');
    assert(isscalar(paths),'Require the original shared physical solver.');p=paths{1};
    required={'UseLocalSolver','LocalSolverChoice','LocalSolverSampleTime','DoFixedCost', ...
        'ConsistencyTolSource','ConsistencyAbsTol','ConsistencyRelTol','ResidualTolerance'};
    optional={'ConsistencyTolFactor','MaxNonlinIter','ResolveIndetEquations','IndexReductionMethod'};
    dialog=get_param(p,'DialogParameters');
    assert(all(isfield(dialog,required)),'Public numerical solver contract changed.');
    fields=[required,optional(isfield(dialog,optional))];
    before=read_settings(model,p,fields);
    assert(strcmp(before.UseLocalSolver,'on') && ...
        strcmp(before.LocalSolverChoice,'NE_BACKWARD_EULER_ADVANCER') && ...
        str2double(before.LocalSolverSampleTime)==.001 && strcmp(before.DoFixedCost,'off'), ...
        'Do not silently change integration or fixed-cost mode.');
    if strcmp(profile,'local_tight')
        set_param(p,'ConsistencyTolSource','LOCAL','ConsistencyAbsTol','1e-12', ...
            'ConsistencyRelTol','1e-9','ResidualTolerance','1e-12');
    end
    after=read_settings(model,p,fields);
    allowed={'ConsistencyTolSource','ConsistencyAbsTol','ConsistencyRelTol','ResidualTolerance'};
    changed={};names=fieldnames(before);
    for k=1:numel(names)
        if ~isequal(before.(names{k}),after.(names{k})),changed{end+1}=names{k};end %#ok<AGROW>
    end
    assert(all(ismember(changed,allowed)),'Unexpected non-consistency change.');
    if strcmp(profile,'inherited'),assert(isempty(changed));end
    contract=struct('schema','heatdrive_ecc_native_consistency_probe_v1','profile',profile, ...
        'solver_path',p,'before',before,'after',after,'changed_parameters',{changed}, ...
        'time_step_or_global_solver_changed',false,'initial_inventory_targets_changed',false, ...
        'material_constitutive_PI_changed',false,'old_OP_loaded',false, ...
        'production_recovery_allowed',false,'a_numerical_experiment_not_a_gate_relaxation',true);
end

function row=read_settings(model,solver,fields)
    row=struct();
    for j=1:numel(fields),row.(fields{j})=get_param(solver,fields{j});end
    row.global_Solver=get_param(model,'Solver');row.global_FixedStep=get_param(model,'FixedStep');
    row.global_RelTol=get_param(model,'RelTol');row.global_AbsTol=get_param(model,'AbsTol');
end

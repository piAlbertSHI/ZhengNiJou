function record=Export_HeatDriveECC_ProfilerDiagnosticsR2025b(repo,out)
% Read version-specific public getters; never edit the archived simulation.
    assert(strcmp(version('-release'),'2025b'),'Internal getter adapter is restricted to R2025b.');
    assert(~isfolder(out) && ~isfile(out),'Never overwrite diagnostic evidence.');
    source=fullfile(repo,'outputs_storage_audit','specific_inventory_hybrid_held_sdi_profiler_20260910','solver_profile.mat');
    expected='C9C6FFA506031B9EC1FE836D4469B7A5F29BBD04C132D95E7BD89EF58163FB2A';
    assert(strcmp(file_hash(source),expected),'Profiler reference changed.');
    model='heatdrive_ecc_coupled_se21';assert(~bdIsLoaded(model));
    ids_before=Simulink.sdi.getAllRunIDs;
    lastwarn('');s=load(source,'sessionData');[warning_message,warning_id]=lastwarn;
    require_public_method(s.sessionData,'getActualDataFromSolverProfilerSessionData');
    wrapper=s.sessionData.getActualDataFromSolverProfilerSessionData();d=wrapper.data;
    assert(strcmp(d.Model,model));
    for name={'getJacobianTableContent','getInaccurateStateTableContent','getJacobianUpdateTime','getTout'}
        require_public_method(d,name{1});
    end
    pd=d.SortedPD;j=pd.JacobianInfo;x=pd.Xout;
    record=struct('adapter_release',version('-release'),'matlab_version',version, ...
        'interface_status','version_specific_public_getters_in_undocumented_internal_namespace', ...
        'simulation_run',false,'source_sha256',expected,'model',model, ...
        'load_warning_id',warning_id,'load_warning_message',warning_message);
    record.jacobian=struct('update_times_s',d.getJacobianUpdateTime(), ...
        'analysis_times_s',j.TJacobian,'mass_times_s',j.TMass,'factor_times_s',j.TFactor, ...
        'reported_condition_numbers',j.CondNum,'reported_stiffness',j.Stiffness, ...
        'limiting_state_table',j.LimitingStateTable,'ranked_table',{d.getJacobianTableContent()}, ...
        'raw_matrices_exported',false,'condition_number_definition_independently_verified',false);
    record.inaccurate_state_table=d.getInaccurateStateTableContent();
    record.solver_times_s=d.getTout();record.state_count=numel(x.Xout);
    record.states=x.Xout;record.state_ranges=x.StatesRange;
    record.state_indices=x.StateIndices;
    record.derivative_times_s=x.ToutForDeriv;
    record.derivative_value_indices=x.XoutValueIdxForDeriv;
    record.state_stats=pd.BlockStateStats.StateStats;
    record.block_stats=pd.BlockStateStats.BlockStats;
    record.reset_model_stats=pd.ResetInfo.ModelResetStats;
    record.reset_block_stats=pd.ResetInfo.BlockResetStats;
    record.reset_times_s=pd.ResetInfo.ResetTime;
    record.compiled_info=pd.CompiledInfo;
    record.public_jacobian_members=public_members(j);
    record.public_state_members=public_members(x);
    record.all_model_state_coverage_verified=false;
    record.actual_error_weights_verified=false;
    record.full_iteration_matrices_analyzed=false;
    record.scientific_balance_gate_pass=false;
    record.production_recovery_allowed=false;
    record.table4_reproduction_claim=false;
    classes={'SolverProfilerSessionDataClass','SolverProfilerDataClass','JacobianInfoClass','StreamedStatesClass'};
    record.adapter_dependencies=cell(size(classes));
    for k=1:numel(classes)
        path=which(['solverprofiler.internal.' classes{k}]);
        assert(isfile(path));
        record.adapter_dependencies{k}=struct('class',classes{k},'file',path,'sha256',file_hash(path));
    end
    assert(strcmp(file_hash(source),expected) && ~bdIsLoaded(model),'Read-only invariant failed.');
    assert(isequal(ids_before,Simulink.sdi.getAllRunIDs),'Archive inspection changed the SDI session.');
    record.source_unchanged=true;record.model_loaded=false;record.sdi_run_ids_unchanged=true;
    record.extractor_sha256=file_hash([mfilename('fullpath') '.m']);
    payload=jsonencode(record,'PrettyPrint',true);
    mkdir(out);fid=fopen(fullfile(out,'profiler_diagnostics.json'),'w','n','UTF-8');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',payload);clear cleanup
    fprintf('%s\n',jsonencode(struct('extraction_pass',true,'state_count',record.state_count, ...
        'jacobian_update_count',numel(j.JacobianTimes),'jacobian_analysis_count',numel(j.TJacobian), ...
        'simulation_run',false,'production_recovery_allowed',false)));
end

function require_public_method(obj,name)
    c=metaclass(obj);m=c.MethodList(strcmp({c.MethodList.Name},name));
    assert(isscalar(m) && isequal(m.Access,'public'),'Required public getter unavailable.');
end

function result=public_members(obj)
    c=metaclass(obj);result=struct('class',c.Name,'properties',{{}},'methods',{{}});
    for k=1:numel(c.PropertyList)
        p=c.PropertyList(k);
        if isequal(p.GetAccess,'public'),result.properties{end+1}=p.Name;end
    end
    for k=1:numel(c.MethodList)
        m=c.MethodList(k);
        if isequal(m.Access,'public') && strcmp(m.DefiningClass.Name,c.Name)
            result.methods{end+1}=struct('name',m.Name,'inputs',{m.InputNames},'outputs',{m.OutputNames});
        end
    end
end

function hash=file_hash(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,1048576,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function record=Test_HeatDriveECC_KernelColdAdmission(admission,parent,qualification,python,old_closeout,root)
% A private parameter/block fixture, not a physical model or a recovery result.
    assert(~isfolder(root));mkdir(root);backend=Read_HeatDriveECC_KernelColdAdmission(admission);
    request=struct('mode','runtime_sensitivity_cold','source_contract_path',parent, ...
        'candidate_qualification_path',qualification,'python_executable',python, ...
        'case_index',2,'probe_only',false,'kernel_admission_path',admission);
    state=struct('mode','capture','command_horizon_cycles',200);
    assert(isequaln(Resolve_HeatDriveECC_ObservationPreflight(request,state,20,200,'native',true,struct()),request));
    fixture_repo=fullfile(root,'admission_fixture');mkdir(fullfile(fixture_repo,'verification'));
    authority=fileparts(fileparts(admission));
    for key={'offline_relative','coupled_relative'}
        rel=backend.(key{1});destination=fullfile(fixture_repo,rel);mkdir(fileparts(destination));copyfile(fullfile(authority,rel),destination);
    end
    rejected=0;
    for k=1:8
        bad=backend;
        switch k
            case 1,bad.old_backend_OP_import_allowed=true;
            case 2,bad.same_case_split_test_required_before_long_continuation=false;
            case 3,bad.production_recovery_allowed=true;
            case 4,bad.kernel_sha256=repmat('0',1,64);
            case 5,bad.coupled_sha256=repmat('0',1,64);
            case 6,bad.offline_sha256=repmat('0',1,64);
            case 7,bad.wrapper_name='HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic';
            case 8,bad.independent_cold_20cycle_admitted=false;
        end
        path=fullfile(fixture_repo,'verification',sprintf('invalid_%02d.json',k));write_json(path,bad);
        failed=false;try,Read_HeatDriveECC_KernelColdAdmission(path);catch,failed=true;end
        assert(failed);rejected=rejected+1;
    end
    source_json=jsondecode(fileread(old_closeout));
    source=Read_HeatDriveECC_SensitivityColdSource(old_closeout,source_json.case_index);
    bad=request;bad.mode='runtime_sensitivity_continuation';bad.case_index=source_json.case_index;
    bad.candidate_qualification_path=source.case_contract.source_qualification_path;
    bad.source_closeout_path=old_closeout;bad.collection_root=fullfile(fileparts(fileparts(mfilename('fullpath'))),'outputs','__kernel_cross_backend_test_not_created');
    bad.resume_collection=false;bad.collection_stop_s=400;
    failed=false;
    try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());
    catch ME,failed=contains(ME.message,'Do not switch backend');end
    assert(failed);rejected=rejected+1;
    q=jsondecode(fileread(qualification));saved=load(fullfile(q.source_packet_root,'native','configuration.mat'),'plant_build_options');
    options=Build_HeatDriveECC_EighthRound_Defaults(saved.plant_build_options);
    options.constitutive.diagnostic_step_function=backend.wrapper_name;
    assignin('base','EIGHTH_ROUND_OPTIONS',options);
    model='heatdrive_kernel_snapshot_unit_fixture';assert(~bdIsLoaded(model));new_system(model);
    cleanup=onCleanup(@() close_system(model,0));
    path=[model '/ECC_Constitutive21_VectorStep'];
    add_block('simulink/User-Defined Functions/Interpreted MATLAB Function',path, ...
        'MATLABFcn',backend.wrapper_name,'OutputDimensions','252','SampleTime','.001');
    snapshot=Snapshot_HeatDriveECC_ConstitutiveBackend(model,options);
    assert(snapshot.function_matches_request && snapshot.base_kernel_parameters_match && snapshot.substeps==32);
    for k=1:2
        if k==1,set_param(path,'MATLABFcn','HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic');
        else,set_param(path,'MATLABFcn',backend.wrapper_name);bad_options=options; ...
                bad_options.material.SE.Delta_h_J_per_kg=options.material.SE.Delta_h_J_per_kg+1; ...
                assignin('base','EIGHTH_ROUND_OPTIONS',bad_options);end
        failed=false;
        try,Snapshot_HeatDriveECC_ConstitutiveBackend(model,options);
        catch ME,failed=strcmp(ME.identifier,'HeatDriveECC:CandidateBackendBinding');end
        assert(failed);rejected=rejected+1;
    end
    assignin('base','EIGHTH_ROUND_OPTIONS',options);clear cleanup
    record=struct('valid_cold_request',true,'valid_actual_block_snapshot',true,'invalid_cases_rejected',rejected, ...
        'physical_model_loaded',false,'simulation_executed',false,'operating_point_loaded',false, ...
        'private_block_fixture_created',true,'fixture_saved_as_SLX',false);
    write_json(fullfile(root,'admission_tests.json'),record);
    fprintf('KERNEL_COLD_ADMISSION_TEST_JSON=%s\n',jsonencode(record));
end
function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

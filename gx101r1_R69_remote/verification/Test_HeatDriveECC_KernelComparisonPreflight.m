function record=Test_HeatDriveECC_KernelComparisonPreflight(closeouts,kernel,parent,python,root)
% File-bound positive/negative request tests. No model or Operating Point load.
    assert(~isfolder(root));mkdir(root);positives=0;rejected=0;
    state=struct('mode','capture','command_horizon_cycles',200);
    for k=1:numel(closeouts)
        q=jsondecode(fileread(closeouts{k}));source=Read_HeatDriveECC_SensitivityColdSource(closeouts{k},q.case_index);
        request=struct('mode','runtime_sensitivity_kernel_cold_comparison','source_contract_path',parent, ...
            'candidate_qualification_path',source.case_contract.source_qualification_path,'python_executable',python, ...
            'case_index',q.case_index,'probe_only',true,'source_closeout_path',closeouts{k},'kernel_qualification_path',kernel);
        assert(isequaln(Resolve_HeatDriveECC_ObservationPreflight(request,state,20,200,'native',true,struct()),request));
        positives=positives+1;
    end
    for k=1:4
        bad=request;
        switch k
            case 1,bad.probe_only=false;
            case 2,bad.case_index=2;
            case 3,bad.resume_collection=true;
            case 4,bad=rmfield(bad,'kernel_qualification_path');
        end
        failed=false;
        try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,failed=true;end
        assert(failed);rejected=rejected+1;
    end
    original=jsondecode(fileread(kernel));
    for k=1:4
        bad=original;
        switch k
            case 1,bad.all_captured_samples_bitwise_equal=false;
            case 2,bad.candidate_source_sha256=repmat('0',1,64);
            case 3,bad.original_L8_option_cases(1).case_index=8;
            case 4,bad.production_recovery_allowed=true;
        end
        path=fullfile(root,sprintf('bad_kernel_%02d.json',k));write_json(path,bad);
        failed=false;try,Read_HeatDriveECC_KernelQualification(path);catch,failed=true;end
        assert(failed);rejected=rejected+1;
    end
    packet=fullfile(root,'comparison_loader_test');mkdir(packet);
    write_json(fullfile(packet,'COMPARISON_ONLY_DO_NOT_RESUME.json'),struct('fixture',true));
    failed=false;
    try,Load_HeatDriveECC_GatedObservationPacket(packet,false,'');
    catch ME,failed=strcmp(ME.identifier,'HeatDriveECC:ComparisonOnlyCheckpoint');end
    assert(failed);rejected=rejected+1;
    record=struct('positive_requests',positives,'negative_requests_rejected',rejected, ...
        'operating_point_loaded',false,'model_loaded',false,'simulation_executed',false);
    write_json(fullfile(root,'preflight_tests.json'),record);
    fprintf('KERNEL_PREFLIGHT_JSON=%s\n',jsonencode(record));
end
function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function record=Test_HeatDriveECC_SensitivityContinuationSource(closeout,parent,qualification,python)
% Pure source/request binding checks, with no model or Operating Point load.
    sealed=jsondecode(fileread(closeout));index=sealed.case_index;
    source=Read_HeatDriveECC_SensitivityColdSource(closeout,index);
    saved=load(fullfile(source.packet_root,'native','configuration.mat'),'options');
    q=jsondecode(fileread(qualification));
    data=load(fullfile(q.source_packet_root,'native','configuration.mat'),'plant_build_options');
    request=struct('mode','runtime_sensitivity_continuation','case_index',index,'probe_only',false, ...
        'source_contract_path',parent,'candidate_qualification_path',qualification,'python_executable',python, ...
        'source_closeout_path',closeout,'resume_collection',false,'collection_stop_s',400, ...
        'collection_root',fullfile(fileparts(fileparts(mfilename('fullpath'))),'outputs','__source_contract_test_not_created'));
    if isfield(source.case_contract,'execution_backend')
        request.kernel_admission_path=source.case_contract.execution_backend.admission_path;
    end
    [~,c]=Apply_HeatDriveECC_RuntimeSensitivity(data.plant_build_options,request);
    assert(isequaln([c.parameters{:}],source.case_contract.parameters(:).'));
    for k=1:numel(c.parameters)
        r=c.parameters{k};parts=strsplit(r.field,'.');v=saved.options;
        for j=1:numel(parts),v=v.(parts{j});end
        assert(isequaln(v,r.after));
    end
    state=struct('mode','capture','command_horizon_cycles',200);
    assert(isequaln(Resolve_HeatDriveECC_ObservationPreflight(request,state,20,200,'native',true,struct()),request));
    rejected=0;
    for name={'probe_only','resume_collection','case_index'}
        bad=request;
        if strcmp(name{1},'probe_only'),bad.probe_only=true;
        elseif strcmp(name{1},'resume_collection'),bad.resume_collection=1;
        else,bad.case_index=mod(index+1,9);end
        try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    end
    assert(rejected==3);
    record=struct('declared_fields_matched',27,'invalid_requests_rejected',rejected, ...
        'operating_point_loaded',false,'simulation_executed',false,'source_case_hash',source.case_contract_sha256);
    fprintf('CONTINUATION_SOURCE_TEST_JSON=%s\n',jsonencode(record));
end

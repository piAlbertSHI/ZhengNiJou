function record=Verify_HeatDriveECC_KernelColdComparison(input,options,folder,chambers,buffers,request,producer)
% A comparison packet is never a twenty-cycle sensitivity or recovery seed.
    Read_HeatDriveECC_KernelQualification(request.kernel_qualification_path);
    q=jsondecode(fileread(request.source_closeout_path));
    assert(q.case_index==request.case_index && q.completed_cycles==20 && q.all_ten_original_packet_gates_pass);
    reference=q.packet_chain(1).packet_root;
    ref_manifest=jsondecode(fileread(fullfile(reference,'packet_manifest.json')));
    ref_gate=jsondecode(fileread(fullfile(reference,'packet_gate.json')));
    assert(ref_gate.gate_pass && strcmp(file_hash(fullfile(reference,'packet_gate.json')),q.packet_chain(1).gate_sha256) && ...
        strcmp(ref_gate.input_sha256.manifest,file_hash(fullfile(reference,'packet_manifest.json'))));
    for k=1:numel(ref_manifest.input_files)
        row=ref_manifest.input_files(k);assert(strcmp(file_hash(fullfile(reference,row.path)),row.sha256));
    end
    assert(isequal(ref_manifest.window_s,[0;20]) || isequal(ref_manifest.window_s,[0 20]));
    assert(strcmp(ref_manifest.complete_OP_sha256,q.packet_chain(1).operating_point_sha256));
    original=jsondecode(fileread(fullfile(reference,'native','sensitivity_case_contract.json')));
    actual=jsondecode(fileread(fullfile(folder,'sensitivity_case_contract.json')));
    assert(isequaln(original.parameters,actual.parameters),'The original physical parameter declaration changed.');
    root=fullfile(folder,'kernel_cold_comparison');assert(~isfolder(root));mkdir(root);
    record=struct('schema','heatdrive_ecc_kernel_cold_comparison_v1','producer',producer,'case_index',q.case_index, ...
        'reference_packet',reference,'reference_manifest_sha256',file_hash(fullfile(reference,'packet_manifest.json')), ...
        'source_closeout_sha256',file_hash(request.source_closeout_path), ...
        'kernel_qualification_sha256',file_hash(request.kernel_qualification_path),'window_s',[0 20], ...
        'source_OP_imported',false,'independent_cold_start',true,'pass',false, ...
        'all_trajectory_arrays_bitwise_equal',false,'production_recovery_allowed',false, ...
        'twenty_cycle_seed_qualified',false,'complete_state_restore_equivalence_evaluated',false,'error_message','');
    try
        packet=fullfile(root,'packet_C002');
        Collect_HeatDriveECC_ObservationPacket(input,[],0,20,packet,options,folder,chambers,buffers, ...
            producer,request.python_executable,'runtime_sensitivity_cold','');
        write_json(fullfile(packet,'COMPARISON_ONLY_DO_NOT_RESUME.json'), ...
            struct('reason','Implementation comparison only; not a long-chain seed','scientific_gate_failed',false));
        comparison=Compare_HeatDriveECC_ObservationPackets(reference,packet,fullfile(root,'trajectory_comparison.json'));
        record.all_trajectory_arrays_bitwise_equal=comparison.states.bitwise_values_equal && ...
            comparison.native.bitwise_values_equal && comparison.sources.bitwise_values_equal && comparison.public.bitwise_values_equal;
        record.all_original_packet_gates_pass=true;
        record.pass=comparison.pass && record.all_trajectory_arrays_bitwise_equal;
        record.comparison_packet=packet;
        record.candidate_simulation_timing=jsondecode(fileread(fullfile(packet,'simulation_timing.json')));
        record.historical_reference_simulation_timing=jsondecode(fileread(fullfile(reference,'simulation_timing.json')));
        record.timing_is_contemporaneous_paired_benchmark=false;
        assert(record.pass,'HeatDriveECC:CoupledKernelDifference','Actual coupled trajectories differ; no backend promotion.');
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
        write_json(fullfile(root,'REJECTED_DO_NOT_RESUME.json'),struct('reason',ME.message,'failed_state_may_propagate',false));
        write_json(fullfile(root,'kernel_cold_comparison.json'),record);rethrow(ME);
    end
    write_json(fullfile(root,'kernel_cold_comparison.json'),record);
end
function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
function h=file_hash(path)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end

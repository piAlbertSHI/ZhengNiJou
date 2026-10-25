function result=Test_HeatDriveECC_ColdAnalysisScope()
    e=struct('schema','heatdrive_ecc_independent_cold_chamber_v2', ...
        'user_authorized_independent_cold_start',true,'c200_state_imported',false, ...
        'production_recovery_allowed',false,'checkpoint_saved',false, ...
        'diagnostic_state_options',struct('mode','off'), ...
        'diagnostic_resume_contract',struct(),'collection_pass',true, ...
        'requested_arm_collection_pass',true,'error_message','', ...
        'start_time_s',0,'stop_time_s',200,'cycle_count',20, ...
        'segment_cycle_count',20,'execution_commit','producer', ...
        'cases',[struct('arm','native','observation_sha256',repmat('A',1,64)), ...
            struct('arm','conservative','observation_sha256',repmat('B',1,64))]);
    completion=struct('arm','native','start_time_s',0,'stop_time_s',200, ...
        'cycle_count',20,'execution_commit','producer','observation_sha256',repmat('A',1,64));
    a=Resolve_HeatDriveECC_ColdAnalysisScope(e,completion,'native',10);
    assert(a.absolute_start_s==100 && ~a.checkpoint_restart_used && ~a.checkpoint_chain_verified);
    completion.arm='conservative';completion.observation_sha256=repmat('B',1,64);
    b=Resolve_HeatDriveECC_ColdAnalysisScope(e,completion,'conservative',2);
    assert(b.absolute_start_s==180 && ~b.operating_point_loaded);
    for k=1:8
        bad=e;c=completion;arm='conservative';window=2;
        switch k
            case 1,bad.c200_state_imported=true;
            case 2,bad.diagnostic_state_options.mode='diagnostic_resume';
            case 3,bad.start_time_s=20;
            case 4,bad.requested_arm_collection_pass=false;
            case 5,c.arm='native';
            case 6,c.observation_sha256=repmat('A',1,64);
            case 7,window=1;
            case 8,bad.cases(2).arm='native';
        end
        rejected=false;try,Resolve_HeatDriveECC_ColdAnalysisScope(bad,c,arm,window);
        catch,rejected=true;end
        assert(rejected,'Invalid cold observation scope accepted.');
    end
    result=struct('native_ten_cycle_scope_pass',true,'conservative_two_cycle_scope_pass',true, ...
        'restart_history_not_fabricated',true,'invalid_scopes_rejected',8);
    fprintf('SCOPE_TEST_JSON=%s\n',jsonencode(result));
end

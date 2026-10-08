function Test_HeatDriveECC_MechanismProvenance()
    options=struct('schedule',struct('tau_cycle_s',10,'stage_durations_s',[2.5 2.5 2.5 2.5], ...
        'stage_start_s',[0 2.5 5 7.5],'stage_end_s',[2.5 5 7.5 10]), ...
        'simulation',struct('fixed_step_s',.001),'validation',struct('mechanism_gate_start_cycle',1));
    physical=struct('time_s',(0:.001:10).','sim_call_count',1, ...
        'authority','physical_simscape_to_workspace_logs');
    provenance=struct('checkpoint_restart_used',false,'checkpoint_chain_verified',false,'sim_call_count',1);
    result=Make_HeatDriveECC_MechanismWindow(physical,options,provenance,'');
    assert(~result.provenance.checkpoint_restart_used);
    provenance.checkpoint_restart_used=true;
    rejected=false;
    try,Make_HeatDriveECC_MechanismWindow(physical,options,provenance,'');
    catch e,rejected=strcmp(e.identifier,'HeatDriveECC:UnverifiedMechanismSource');end
    assert(rejected,'An unverified actual restart was accepted.');
    provenance.checkpoint_chain_verified=true;
    Make_HeatDriveECC_MechanismWindow(physical,options,provenance,'');
end

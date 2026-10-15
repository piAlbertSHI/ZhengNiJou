function Test_HeatDriveECC_RuntimeTcSource(path)
% Reject wrong-family, reset, changed-Tc and failed-physics sources before sim.
    q=jsondecode(fileread(path));o=struct('system',struct('Tchex_K',276.95,'cold_boundary_temperature_configurability','runtime'));
    source=Require_HeatDriveECC_RuntimeTcSource(q,o);assert(source.snapshot_s==q.snapshot_time_s);
    rejected=0;
    for name={'schema','temperature_K','source_state_edited','snapshot_time_s', ...
            'all_four_memories_bitwise_preserved','all_original_packet_mechanism_flow_phase_energy_gates_pass'}
        bad=q;
        switch name{1}
            case 'schema',bad.schema='C200';
            case 'temperature_K',bad.temperature_K=q.temperature_K+.2;
            case 'snapshot_time_s',bad.snapshot_time_s=q.snapshot_time_s+10;
            case 'source_state_edited',bad.source_state_edited=true;
            otherwise,bad.(name{1})=false;
        end
        try,Require_HeatDriveECC_RuntimeTcSource(bad,o);catch,rejected=rejected+1;end
    end
    assert(rejected==6);fprintf('RUNTIME_TC_SOURCE_POLICY_JSON=%s\n',jsonencode(struct('valid_source',true,'rejected',rejected)));
end

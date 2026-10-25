function Test_HeatDriveECC_CompletedColdObservationComparison(folder)
    assert(~isfolder(folder));mkdir(folder);t=(0:2)'*.001;
    row=struct('block_path','fixture/pipe','state_name','T_I','unit','K', ...
        'time_s',t,'values',[300;301;302]);
    reference=struct();reference.signals.x=struct('time_s',t,'values',[1;2;3]);
    reference.native={row};row.state_name='Q_H';row.unit='W';reference.source_traces={row};
    reference.thermal_boundary_signals.fields.q=struct('time_s',t,'values',[NaN;10;20]);
    candidate=reference;candidate.thermal_boundary_signals.fields.q.values=[7;10;20];
    ref_root=fullfile(folder,'reference');write_case(ref_root,reference);
    good=fullfile(folder,'good');write_case(good,candidate);
    r=Compare_HeatDriveECC_CompletedColdObservation(ref_root,good,fullfile(folder,'good.json'));
    assert(r.pass && r.arms{1}.reference_gaps{1}.unmeasured_reference_samples==1);
    for test={'changed_thermal','changed_public','nonfinite_candidate'}
        data=candidate;
        switch test{1}
            case 'changed_thermal',data.thermal_boundary_signals.fields.q.values(3)=21;
            case 'changed_public',data.signals.x.values(1)=1.1;
            case 'nonfinite_candidate',data.thermal_boundary_signals.fields.q.values(1)=NaN;
        end
        root=fullfile(folder,test{1});write_case(root,data);
        file=fullfile(folder,[test{1} '.json']);rejected=false;
        try,Compare_HeatDriveECC_CompletedColdObservation(ref_root,root,file);catch,rejected=true;end
        assert(rejected);
        if ~strcmp(test{1},'nonfinite_candidate')
            record=jsondecode(fileread(file));assert(~record.pass);
            if strcmp(test{1},'changed_thermal'),expected='thermal/q';else,expected='signals/x';end
            assert(strcmp(record.arms(1).differences.trace,expected));
        end
    end
    fprintf('COMPARISON_TEST_JSON=%s\n',jsonencode(struct('cases',4,'pass',true, ...
        'missing_reference_not_interpolated',true,'changed_measured_values_rejected',true)));
end

function write_case(root,data)
    commands=struct('clock',[0;.001;.002],'flow',[0;1;0]);
    for arm={'native','conservative'}
        folder=fullfile(root,arm{1});mkdir(folder);
        save(fullfile(folder,'observations.mat'),'-struct','data','-v7.3');
        save(fullfile(folder,'configuration.mat'),'commands','-v7.3');
    end
end

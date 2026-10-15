function result=Test_HeatDriveECC_BufferColdFactorial(proof_path)
    empty=Resolve_HeatDriveECC_BufferColdFactorial(struct(),'off',1,10,'native',true);
    assert(isempty(fieldnames(empty)),'Empty options must preserve legacy behavior.');
    count=0;
    for geometry={'inherited','sma_pipe_matched'}
        for precision={'inherited','local_tight'}
            o=struct('geometry',geometry{1},'precision',precision{1},'component_audit_path',proof_path);
            assert(isequaln(o,Resolve_HeatDriveECC_BufferColdFactorial(o,'off',1,10,'native',true)));count=count+1;
        end
    end
    o=struct('geometry','inherited','precision','local_tight','component_audit_path',proof_path);
    rejected=0;
    bad={@() Resolve_HeatDriveECC_BufferColdFactorial(o,'diagnostic_resume',20,200,'native',true), ...
        @() Resolve_HeatDriveECC_BufferColdFactorial(o,'restore_preflight',2,20,'native',true), ...
        @() Resolve_HeatDriveECC_BufferColdFactorial(o,'off',1,10,'both',true), ...
        @() Resolve_HeatDriveECC_BufferColdFactorial(o,'off',1,10,'native',false)};
    wrong=o;wrong.geometry='arbitrary';bad{end+1}=@() Resolve_HeatDriveECC_BufferColdFactorial(wrong,'off',1,10,'native',true);
    extra=o;extra.reset_PI=true;bad{end+1}=@() Resolve_HeatDriveECC_BufferColdFactorial(extra,'off',1,10,'native',true);
    missing=rmfield(o,'component_audit_path');bad{end+1}=@() Resolve_HeatDriveECC_BufferColdFactorial(missing,'off',1,10,'native',true);
    for k=1:numel(bad)
        failed=false;try,bad{k}();catch,failed=true;end
        assert(failed,'Unsafe mode accepted.');rejected=rejected+1;
    end
    result=struct('default_no_op_pass',true,'cold_factor_levels_passed',count,'unsafe_modes_rejected',rejected, ...
        'simulation_executed',false,'operating_point_loaded',false,'production_recovery_allowed',false);
    fprintf('FACTOR_TEST_JSON=%s\n',jsonencode(result));
end

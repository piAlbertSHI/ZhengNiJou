function result = Verify_HeatDriveECC_ManifoldStorageClosureDiagnostic()
    candidate=struct('storage_closure','pressure_only_density');
    Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(candidate,'off',1,10,'native',true);
    Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(struct('volume_factor',1),'off',1,10,'native',true);
    failures={ ...
        @() Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(candidate,'diagnostic_resume',20,200,'native',true), ...
        @() Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(candidate,'off',20,200,'native',true), ...
        @() Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(candidate,'off',1,10,'both',true), ...
        @() Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(struct('storage_closure','pressure_only_density','volume_factor',0.1),'off',1,10,'native',true), ...
        @() Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(struct('storage_closure','fixed_density'),'off',1,10,'native',true)};
    for k=1:numel(failures)
        rejected=false;try,failures{k}();catch,rejected=true;end
        assert(rejected,'Unsafe inventory-density intervention was not rejected.');
    end
    result=struct('positive_cases',2,'negative_cases',numel(failures),'pass',true);
    fprintf('%s\n',jsonencode(result));
end

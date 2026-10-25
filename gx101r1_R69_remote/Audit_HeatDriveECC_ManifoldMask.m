function [pass, record] = Audit_HeatDriveECC_ManifoldMask(chamber, options)
% Native identity remains strict; endpoint diagnostics require exact source binding.
    diagnostic=isfield(options.branch,'independent_conservative_chamber_diagnostic') && ...
        options.branch.independent_conservative_chamber_diagnostic;
    common=strcmp(get_param(chamber,'volume'),'sma_pump_manifold_volume_m3') && ...
        strcmp(get_param(chamber,'p_I'),'sma_pump_manifold_p_init_MPa') && ...
        strcmp(get_param(chamber,'p_I_priority'),'Low') && ...
        strcmp(get_param(chamber,'T_I'),'sma_pump_manifold_T_init_K') && ...
        strcmp(get_param(chamber,'T_I_priority'),'Low');
    source_bound=false; source_sha256=''; library_sha256='';
    if diagnostic
        % Other historical diagnostic variants are not implicitly qualified.
        pressure_only=isfield(options.branch,'diagnostic_manifold_storage_closure') && ...
            strcmp(options.branch.diagnostic_manifold_storage_closure,'pressure_only_density');
        package='ecc_inventory_endpoint';folder='simscape_inventory_endpoint';
        library_name='ecc_inventory_endpoint_lib';chamber_source='ecc_inventory_endpoint.conservative_chamber';
        if pressure_only
            package='ecc_inventory_pressure_only';folder='simscape_inventory_pressure_only';
            library_name='ecc_inventory_pressure_only_lib';chamber_source='ecc_inventory_pressure_only.conservative_chamber';
        elseif strcmp(options.branch.independent_conservative_chamber_library,'ecc_inventory_specific_lib')
            package='ecc_inventory_specific';folder='simscape_inventory_specific';
            library_name='ecc_inventory_specific_lib';chamber_source='ecc_inventory_specific.conservative_chamber';
        end
        supported=strcmp(options.branch.independent_conservative_chamber_library,library_name) && ...
            strcmp(get_param(chamber,'SourceFile'),chamber_source);
        ports=get_param(chamber,'PortHandles');
        geometry=supported && numel(ports.LConn)==2 && numel(ports.RConn)==1 && ...
            strcmp(get_param(chamber,'volume_unit'),'m^3') && ...
            strcmp(get_param(chamber,'area'),'sma_connecting_pipe_flow_area_m2') && ...
            strcmp(get_param(chamber,'area_unit'),'m^2');
        if supported && bdIsLoaded(library_name)
            loaded=get_param(library_name,'FileName');
            actual=fullfile(fileparts(loaded),['+' package],'conservative_chamber.ssc');
            canonical=fullfile(fileparts(mfilename('fullpath')),'verification', ...
                folder,['+' package],'conservative_chamber.ssc');
            source_sha256=file_hash(canonical); library_sha256=file_hash(loaded);
            source_bound=strcmp(file_hash(actual),source_sha256);
        end
        pass=common && geometry && source_bound;
        kind='explicit_conservative_endpoint_diagnostic';
        if pressure_only,kind='pressure_only_inventory_density_diagnostic';end
        if strcmp(package,'ecc_inventory_specific'),kind='explicit_conservative_specific_inventory_diagnostic';end
    else
        pass=common && strcmp(get_param(chamber,'MaskType'),sprintf('Constant Volume\nChamber (TL)')) && ...
            strcmp(get_param(chamber,'num_ports'),'foundation.enum.num_ports.two') && ...
            strcmp(get_param(chamber,'area_A'),'sma_connecting_pipe_flow_area_m2') && ...
            strcmp(get_param(chamber,'area_B'),'sma_connecting_pipe_flow_area_m2');
        kind='native_constant_volume_chamber';
    end
    record=struct('implementation',kind,'common_masks_pass',common, ...
        'exact_endpoint_source_bound',source_bound,'source_sha256',source_sha256, ...
        'library_sha256',library_sha256,'mask_pass',pass,'diagnostic_only',diagnostic, ...
        'inventory_runtime_gate_evaluated',false,'production_recovery_allowed',false);
end

function hash=file_hash(file)
    fid=fopen(file,'rb');assert(fid>=0,'Missing source-qualified diagnostic component.');
    cleanup=onCleanup(@() fclose(fid));digest=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

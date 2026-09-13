function [point,runtime_targets,contract]=Build_HeatDriveECC_ColdInitialFluxCompensation(repo,model,native,physical_targets)
% Precondition public High targets using the measured cold-start flux signature.
    signature_path=fullfile(repo,'outputs_storage_audit','cold_initial_flux_signature_20260909_v2', ...
        'initial_flux_signature.json');
    assert(strcmp(file_hash(signature_path),'321EB63473C47F83D939BC535B3B329924E92CB38D5DD3F2B53C52B869AA8203'), ...
        'Cold initial-flux prerequisite changed.');
    signature=jsondecode(fileread(signature_path));
    step=2e-5;
    assert(signature.evidence_audit_pass && signature.post_hoc_hypothesis && ...
        signature.inventory_groups.energy.hypothesis_step_s==step && ...
        signature.inventory_groups.energy.signature_within_limit && ...
        signature.inventory_groups.mass.signature_within_limit && ...
        ~signature.initialization_repair_verified && ~signature.solver_internal_step_proven && ...
        ~signature.targets_modified && ~signature.production_recovery_allowed, ...
        'Initial-flux evidence does not authorize this bounded diagnostic.');
    assert(numel(physical_targets)==204 && sum(cellfun(@(t) strcmp(t.priority,'High'),physical_targets))==125, ...
        'Require the complete physical cold target contract.');

    point=simscape.op.OperatingPoint;
    runtime_targets=cell(size(physical_targets));
    corrections=cell(1,125);corrected=0;
    for k=1:numel(physical_targets)
        physical=physical_targets{k};runtime=physical;
        if strcmp(physical.priority,'High')
            [rate,rate_unit]=target_rate(model,native,physical);
            delta=value(simscape.Value(rate,rate_unit)*simscape.Value(step,'s'),physical.unit);
            runtime.value=physical.value-delta;
            assert(isfinite(runtime.value),'Nonfinite compensated cold target.');
            corrected=corrected+1;
            corrections{corrected}=struct('path',physical.path,'block_path',physical.block_path, ...
                'state_name',physical.state_name,'unit',physical.unit,'physical_value',physical.value, ...
                'rate',rate,'rate_unit',rate_unit,'hypothesis_step_s',step, ...
                'subtracted_delta',delta,'runtime_value',runtime.value,'priority',physical.priority);
        end
        point=set(point,runtime.path,simscape.op.Target(runtime.value,runtime.unit,runtime.priority));
        runtime_targets{k}=runtime;
    end
    assert(corrected==125 && ~hasPrivateData(point),'Incomplete public flux compensation.');
    contract=struct('schema','heatdrive_ecc_cold_initial_flux_compensation_v1', ...
        'diagnostic_prerequisite',signature_path,'diagnostic_prerequisite_sha256',file_hash(signature_path), ...
        'hypothesis_step_s',step,'physical_target_count',numel(physical_targets), ...
        'corrected_high_target_count',corrected,'unchanged_low_target_count',numel(physical_targets)-corrected, ...
        'corrections',{corrections},'physical_targets',{physical_targets}, ...
        'runtime_targets',{runtime_targets},'private_state_imported',false, ...
        'solver_internal_step_claimed',false,'production_recovery_allowed',false);
end

function [rate,unit]=target_rate(model,native,target)
    path=target.block_path;mask=get_param(path,'MaskType');name=target.state_name;
    if strcmp(mask,'Pipe (TL)')
        assert(strcmp(name,'u_I'),'Unexpected High pipe target.');
        rho=nominal_density(model,path);
        area=value(simscape.Value(slResolve(get_param(path,'area'),path),get_param(path,'area_unit')),'m^2');
        length=value(simscape.Value(slResolve(get_param(path,'length'),path),get_param(path,'length_unit')),'m');
        mass=rho*area*length;
        rate=(initial(native,path,'Phi_A','W')+initial(native,path,'Phi_B','W')+ ...
            initial(native,path,'Q_H','W'))/mass;
        unit='J/(kg*s)';
    elseif strcmp(mask,'Thermal Mass')
        assert(strcmp(name,'T'),'Unexpected High solid target.');
        mass=value(simscape.Value(slResolve(get_param(path,'mass'),path),get_param(path,'mass_unit')),'kg');
        cp=value(simscape.Value(slResolve(get_param(path,'sp_heat'),path),get_param(path,'sp_heat_unit')),'J/(kg*K)');
        rate=initial(native,path,'Q','W')/(mass*cp);
        unit='K/s';
    elseif contains(mask,'Buffer')
        if strcmp(name,'stored_mass')
            rate=initial(native,path,'mdot_A','kg/s');unit='kg/s';
        else
            assert(strcmp(name,'stored_energy'),'Unexpected High buffer target.');
            rate=initial(native,path,'Phi_A','W')+initial(native,path,'Q_H','W');unit='W';
        end
    elseif contains(mask,'Chamber')
        if strcmp(name,'stored_mass')
            rate=initial(native,path,'mdot_A','kg/s')+initial(native,path,'mdot_B','kg/s');unit='kg/s';
        else
            assert(strcmp(name,'stored_energy'),'Unexpected High chamber target.');
            rate=initial(native,path,'Phi_A','W')+initial(native,path,'Phi_B','W')+ ...
                initial(native,path,'Q_H','W');unit='W';
        end
    else
        error('HeatDriveECC:UnknownCompensatedTarget','Unsupported High target: %s/%s',mask,name);
    end
    assert(isfinite(rate),'Nonfinite initial target rate.');
end

function rho=nominal_density(model,path)
    settings=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block');
    mask_types=get_param(settings,'MaskType');
    settings=settings(cellfun(@(mask) contains(mask,'Thermal Liquid') && ...
        contains(mask,'Settings (TL)'),mask_types));
    assert(numel(settings)==2,'Require the two unchanged fluid property tables.');
    index=1;if contains(path,'/SE/'),index=2;end
    block=settings{index};
    temperatures=slResolve(get_param(block,'T_TLU'),block);
    densities=slResolve(get_param(block,'rho_TLU_4'),block);
    nominal_temperature=str2double(get_param(path,'T_nominal'));
    rho=interp1(double(temperatures(:)),double(densities(:)),nominal_temperature,'linear','extrap');
    assert(isfinite(rho) && rho>0,'Nonfinite nominal pipe density.');
end

function result=initial(rows,path,name,unit)
    selected=rows(cellfun(@(r) strcmp(r.block_path,path) && strcmp(r.state_name,name),rows));
    assert(isscalar(selected) && selected{1}.time_s(1)==0,'Missing native initial flux coordinate.');
    result=value(simscape.Value(selected{1}.values(1),selected{1}.unit),unit);
    assert(isfinite(result),'Nonfinite native initial flux coordinate.');
end

function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0,'Missing prerequisite.');
    cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end

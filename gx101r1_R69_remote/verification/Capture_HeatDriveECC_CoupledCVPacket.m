function record=Capture_HeatDriveECC_CoupledCVPacket(output,model,options,contract,folder)
% Save disjoint raw groups immediately; never an aggregate duplicate packet.
    chambers={};buffers={};
    if strcmp(contract.schema,'heatdrive_ecc_endpoint_CV_inventory_v1')
        chambers=contract.endpoint_chamber_paths;buffers=contract.endpoint_buffer_paths;
    end
    [native,profiling]=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false,chambers,buffers,contract);
    packet=Pack_HeatDriveECC_TraceColumns(native); %#ok<NASGU>
    file=fullfile(folder,'native_CV_observations.mat');assert(~isfile(file));save(file,'packet','-v7');
    record=struct('native_file',file,'native_sha256',file_hash(file),'native_trace_count',numel(native), ...
        'component_count',numel(contract.storage_paths),'native_leaf_profile',profiling, ...
        'observational_only',true,'production_recovery_allowed',false);
    record.contract_file_sha256=contract.capture_file_sha256;
    initials=native(cellfun(@(r)strcmp(r.state_name,'T_I') && ...
        ~isempty(regexp(r.block_path,'/SMA/(Hold|Cooldown)Pipe_[0-9]{3}$','once')),native));
    expected=42;if strcmp(contract.variant,'shared'),expected=21;end
    assert(numel(initials)==expected && all(cellfun(@(r)r.time_s(1)==0,initials)));
    temps=cellfun(@(r)value(simscape.Value(r.values(1),r.unit),'K'),initials);
    record.maximum_initial_SMA_pipe_temperature_error_K=max(abs(temps-options.system.T0_K));
    record.native_time_grid_count=numel(packet.time_grids);
    write_json(fullfile(folder,'native_CV_saved.json'),record);
    clear packet native
    available=output.who;
    assert(isempty(setdiff(contract.required_workspace_variables,available)), ...
        'Actual simulation did not return a required flow, outlet, pressure or constitutive signal.');
    traces={};skipped={};
    for k=1:numel(contract.workspace_variables)
        name=contract.workspace_variables{k};
        if ~ismember(name,available),skipped{end+1}=name;continue;end %#ok<AGROW>
        v=output.get(name);
        if isstruct(v) && isfield(v,'time') && isfield(v,'signals') && isfield(v.signals,'values')
            t=double(v.time(:));data=double(v.signals.values);
        elseif isa(v,'timeseries')
            t=double(v.Time(:));data=double(v.Data);
        else
            assert(~ismember(name,contract.required_workspace_variables),'Unsupported core signal format.');
            skipped{end+1}=name;continue; %#ok<AGROW>
        end
        data=squeeze(data);
        if isvector(data),data=data(:);
        elseif size(data,1)~=numel(t) && size(data,2)==numel(t),data=data.';end
        assert(ismatrix(data) && size(data,1)==numel(t),'Do not flatten time and spatial dimensions.');
        assert(all(isfinite(data),'all'),'Nonfinite actual workspace signal.');
        traces{end+1}=struct('block_path',model,'state_name',name,'unit','model-signal', ...
            'time_s',t,'values',data,'channel_count',size(data,2)); %#ok<AGROW>
    end
    packet=Pack_HeatDriveECC_TraceColumns(traces); %#ok<NASGU>
    file=fullfile(folder,'workspace_CV_observations.mat');assert(~isfile(file));save(file,'packet','-v7');
    record.workspace_file=file;record.workspace_sha256=file_hash(file);
    record.workspace_signal_count=numel(traces);record.optional_variables_not_recorded=skipped;
    write_json(fullfile(folder,'workspace_CV_saved.json'),record);clear packet traces
    [sources,boundary]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model,contract.tl_topology,contract.thermal_topology);
    packet=Pack_HeatDriveECC_TraceColumns(sources); %#ok<NASGU>
    file=fullfile(folder,'source_CV_observations.mat');assert(~isfile(file));save(file,'packet','boundary','-v7');
    record.source_file=file;record.source_sha256=file_hash(file);record.source_count=boundary.source_count;
    file=fullfile(folder,'CV_options.mat');assert(~isfile(file));save(file,'options','-v7');
    record.options_file=file;record.options_sha256=file_hash(file);
    record.collection_complete=true;record.full_mechanism_or_periodic_qualification=false;
    write_json(fullfile(folder,'completed_CV_packet.json'),record);
end

function h=file_hash(p)
    f=fopen(p,'rb');assert(f>=0);c=onCleanup(@() fclose(f));d=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(f),d.update(fread(f,1048576,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end

function write_json(p,r)
    assert(~isfile(p));f=fopen(p,'w','n','UTF-8');assert(f>=0);c=onCleanup(@() fclose(f));
    fprintf(f,'%s',jsonencode(r,'PrettyPrint',true));
end

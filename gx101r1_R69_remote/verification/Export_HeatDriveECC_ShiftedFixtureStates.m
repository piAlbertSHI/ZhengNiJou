function report=Export_HeatDriveECC_ShiftedFixtureStates(repo,out)
% Reload saved Dataset values without constructing or simulating a model.
    assert(~isfolder(out),'Never overwrite state evidence.');
    manifest_path=fullfile(repo,'outputs_storage_audit','reset_coordinate_package_20260910','reset_coordinate_package.json');
    assert(strcmp(file_hash(manifest_path),'4FB2B282E68F78211C200D014722DD54BD249147ECFB441F86243D7491372D81'));
    manifest=jsondecode(fileread(manifest_path));
    before=find_system('Type','block_diagram');
    report=struct('read_only',true,'model_simulated',false,'production_recovery_allowed',false, ...
        'cases',{{}},'matlab_release',version('-release'),'source_manifest_sha256',file_hash(manifest_path));
    for mode={'closed','flow'}
        root=fullfile(repo,'outputs_storage_audit',['shifted_inventory_' mode{1} '_fixture_20260910']);
        for k=1:8
            file=fullfile(root,sprintf('case_%02d.mat',k));relative=erase(file,[repo filesep]);
            rows=manifest.files(strcmp({manifest.files.path},relative));assert(isscalar(rows));
            assert(strcmp(file_hash(file),rows.sha256),'Saved fixture changed.');
            saved=load(file,'states');dataset=saved.states;
            assert(isa(dataset,'Simulink.SimulationData.Dataset'));
            states=cell(1,dataset.numElements);
            for n=1:dataset.numElements
                s=dataset.getElement(n);v=s.Values;assert(isa(v,'timeseries'));
                entry=struct('name',s.Name,'class',class(s),'block_path',{s.BlockPath.convertToCell}, ...
                    'time_s',v.Time,'data',v.Data,'unit',v.DataInfo.Units,'properties',{properties(s)});
                if isprop(s,'Label'),entry.label=s.Label;end
                states{n}=entry;
            end
            report.cases{end+1}=struct('mode',mode{1},'case_index',k,'source',relative, ...
                'source_sha256',rows.sha256,'states',{states});
            assert(strcmp(file_hash(file),rows.sha256),'Read-only source changed.');
        end
    end
    assert(isequal(before,find_system('Type','block_diagram')),'Reload unexpectedly opened a model.');
    report.model_inventory_unchanged=true;
    mkdir(out);fid=fopen(fullfile(out,'shifted_fixture_states.json'),'w','n','UTF-8');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(struct('read_only_export_pass',true,'cases',numel(report.cases))));
end

function hash=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));digest.update(fread(fid,Inf,'*uint8'));
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

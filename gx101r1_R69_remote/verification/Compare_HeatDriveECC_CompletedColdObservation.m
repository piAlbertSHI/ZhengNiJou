function result=Compare_HeatDriveECC_CompletedColdObservation(reference_root,candidate_root,destination)
% Passive-observation equivalence only on actual measured reference samples.
    assert(~isfile(destination));result=struct('pass',true,'arms',{{}}, ...
        'comparison_only',true,'simulation_executed',false,'production_recovery_allowed',false);
    for arm={'native','conservative'}
        reference_path=fullfile(reference_root,arm{1},'observations.mat');
        candidate_path=fullfile(candidate_root,arm{1},'observations.mat');
        reference=load(reference_path);candidate=load(candidate_path);
        count=0;differences={};coverage={};
        for name=fieldnames(reference.signals).'
            assert(isfield(candidate.signals,name{1}));
            compare(reference.signals.(name{1}),candidate.signals.(name{1}), ...
                ['signals/' name{1}],false);
        end
        for group={'native','source_traces'}
            a=reference.(group{1});b=candidate.(group{1});assert(numel(a)==numel(b));
            for k=1:numel(a)
                assert(strcmp(a{k}.block_path,b{k}.block_path) && ...
                    strcmp(a{k}.state_name,b{k}.state_name) && strcmp(a{k}.unit,b{k}.unit));
                compare(a{k},b{k},[group{1} '/' b{k}.block_path '/' b{k}.state_name],false);
            end
        end
        for name=fieldnames(reference.thermal_boundary_signals.fields).'
            a=reference.thermal_boundary_signals.fields.(name{1});
            b=candidate.thermal_boundary_signals.fields.(name{1});
            assert(all(isfinite(b.values),'all'),'Nonfinite candidate thermal field.');
            compare(a,b,['thermal/' name{1}],true);
        end
        a=load(fullfile(reference_root,arm{1},'configuration.mat'),'commands');
        b=load(fullfile(candidate_root,arm{1},'configuration.mat'),'commands');
        assert(isequaln(a.commands,b.commands),'Changed cold command schedule.');
        entry=struct('arm',arm{1},'compared_traces',count,'bitwise_equal',isempty(differences), ...
            'differences',{differences},'reference_gaps',{coverage}, ...
            'commands_bitwise_equal',true,'thermal_fields_finite',true, ...
            'reference_observations_sha256',file_hash(reference_path), ...
            'candidate_observations_sha256',file_hash(candidate_path));
        result.arms{end+1}=entry;result.pass=result.pass && entry.bitwise_equal;
        clear reference candidate a b
    end
    result.reference_root=reference_root;result.candidate_root=candidate_root;
    fid=fopen(destination,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(result,'PrettyPrint',true));clear c
    fprintf('COMPARISON_JSON=%s\n',jsonencode(struct('pass',result.pass, ...
        'simulation_executed',false,'arms',{cellfun(@(a) struct('arm',a.arm, ...
        'traces',a.compared_traces,'bitwise_equal',a.bitwise_equal),result.arms,'UniformOutput',false)})));
    assert(result.pass,'Changed measured values; inspect the immutable comparison evidence.');

    function compare(a,b,label,allow_reference_gaps)
        ta=double(a.time_s(:));tb=double(b.time_s(:));
        [present,indices]=ismember(tb,ta);assert(all(present),'Unmatched measured clock: %s',label);
        av=reshape(a.values,numel(ta),[]);bv=reshape(b.values,numel(tb),[]);
        assert(size(av,2)==size(bv,2));count=count+1;
        observed=true(numel(tb),1);
        if allow_reference_gaps
            observed=all(isfinite(av(indices,:)),2);assert(any(observed));
            if any(~observed)
                coverage{end+1}=struct('trace',label,'unmeasured_reference_samples',sum(~observed), ...
                    'compared_samples',sum(observed),'first_compared_s',tb(find(observed,1)), ...
                    'last_compared_s',tb(find(observed,1,'last'))); %#ok<AGROW>
            end
        end
        expected=av(indices(observed),:);actual=bv(observed,:);
        if ~isequaln(expected,actual)
            delta=abs(double(expected)-double(actual));
            differences{end+1}=struct('trace',label,'max_abs_difference',max(delta,[],'all')); %#ok<AGROW>
        end
    end
end

function hash=file_hash(path)
    md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);
    c=onCleanup(@() fclose(fid));while ~feof(fid),md.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end

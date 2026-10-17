function review=Review_HeatDriveECC_ConstructorSourceDelta(workspace,producer,path)
% Accept only an exact append-only permission extension on an old accepted constructor.
    assert(~isfile(path),'Never overwrite a source-delta review.');
    selector=['":(top,glob)gx101r1_R69_remote/*.m" ' ...
        '"gx101r1_R69_remote/verification/Integrate_HeatDriveECC_StableConstitutiveSample.m" ' ...
        '"gx101r1_R69_remote/verification/HeatDriveECC_ConstitutiveStabilityBound.m"'];
    [status,out]=system(sprintf('git -c core.longpaths=true -C "%s" diff --name-only "%s" HEAD -- %s',workspace,producer,selector));
    assert(status==0);changed=cellstr(splitlines(strtrim(string(out))));
    changed=changed(~cellfun(@isempty,changed));
    checker='gx101r1_R69_remote/Check_HeatDriveECC_DiagnosticManifoldGeometry.m';
    assert(isempty(setdiff(changed,{checker})),'A numerical constructor or constitutive source changed.');
    review=struct('schema','heatdrive_ecc_constructor_source_delta_v1','producer',producer, ...
        'changed_constructor_sources',{changed},'numerical_sources_unchanged',true, ...
        'legacy_accepted_geometry_path_unchanged',true,'permission_extension_only',~isempty(changed), ...
        'scientific_thresholds_changed',false);
    if ~isempty(changed)
        [status,old]=system(sprintf('git -c core.longpaths=true -C "%s" show "%s:%s"',workspace,producer,checker));assert(status==0);
        old=strrep(old,sprintf('\r\n'),sprintf('\n'));current=strrep(fileread(fullfile(workspace,checker)),sprintf('\r\n'),sprintf('\n'));
        ending=sprintf('end\n');assert(endsWith(old,ending));prefix=old(1:end-numel(ending));
        suffix=sprintf('    if ~allowed\n        allowed=Check_HeatDriveECC_ColdL8ManifoldGeometry(options);\n    end\nend\n');
        assert(isequal(current,[prefix suffix]),'Only the exact guarded append is a nonnumerical source exception.');
        [status,blob]=system(sprintf('git -c core.longpaths=true -C "%s" rev-parse "%s:%s"',workspace,producer,checker));assert(status==0);
        review.legacy_checker_git_blob=strtrim(blob);
    end
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(review,'PrettyPrint',true));
end

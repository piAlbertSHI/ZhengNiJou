function config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(prepared_root,parent_path)
% Rebuild the qualified runtime family without loading any old-family OP.
    repo=fileparts(fileparts(mfilename('fullpath')));workspace=fileparts(repo);
    assert(~isfolder(prepared_root) && ~isfile([prepared_root,'.preflight_config.json']));
    [code,dirty]=system(sprintf('git -C "%s" status --porcelain',workspace));assert(code==0 && isempty(strtrim(dirty)));
    parent=jsondecode(fileread(parent_path));
    source=fullfile(parent.execution_repo,parent.source_root_relative);
    config=jsondecode(fileread([source,'.resumed_config.json']));
    config.repo_root=repo;config.output_root=prepared_root;
    config.duration_s=200;config.cycle_count=20;config.diagnostic_arm='native';
    config.diagnostic_state_options=struct('mode','capture','command_horizon_cycles',200);
    for name={'diagnostic_inventory_options','diagnostic_se_reference_options'}
        value=config.(name{1});
        for key={'rebuilt_state_audit_path','warmup_restore_audit_path'}
            if isfield(value,key{1}),value=rmfield(value,key{1});end
        end
        config.(name{1})=value;
    end
end

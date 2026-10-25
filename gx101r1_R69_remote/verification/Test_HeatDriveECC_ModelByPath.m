function Test_HeatDriveECC_ModelByPath(output_root)
    assert(~isfolder(output_root),'Never overwrite loader fixture evidence.');
    mkdir(output_root);a=fullfile(output_root,'a');b=fullfile(output_root,'b');mkdir(a);mkdir(b);
    model='ecc_model_path_fixture';assert(~bdIsLoaded(model));
    cleanup_model=onCleanup(@() close_fixture(model));
    new_system(model);set_param(model,'Description','expected');save_system(model,fullfile(a,[model '.slx']));
    close_system(model,0);new_system(model);set_param(model,'Description','wrong-worktree');
    save_system(model,fullfile(b,[model '.slx']));close_system(model,0);
    olddir=pwd;restore_dir=onCleanup(@() cd(olddir));cd(b);
    requested=fullfile(a,[model '.slx']);Load_HeatDriveECC_ModelByPath(requested,model);
    assert(strcmp(get_param(model,'Description'),'expected'));
    Load_HeatDriveECC_ModelByPath(requested,model);close_system(model,0);
    load_system(fullfile(b,[model '.slx']));rejected=false;
    try,Load_HeatDriveECC_ModelByPath(requested,model);catch,rejected=true;end
    assert(rejected && bdIsLoaded(model) && strcmp(get_param(model,'Description'),'wrong-worktree'));
    fprintf('MODEL_PATH_TEST_JSON=%s\n',jsonencode(struct('cases',3,'pass',true, ...
        'simulation_executed',false,'conflicting_model_preserved',true)));
end

function close_fixture(model)
    if bdIsLoaded(model),close_system(model,0);end
end

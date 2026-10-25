function loaded_path=Load_HeatDriveECC_ModelByPath(model_path,model_name)
% Same-name models in another worktree must never satisfy a path contract.
    requested=char(java.io.File(model_path).getCanonicalPath());
    assert(isfile(requested),'Canonical model file is missing.');
    [~,name]=fileparts(requested);
    assert(strcmp(name,model_name),'Requested model name differs from its file.');
    if bdIsLoaded(model_name)
        actual=char(java.io.File(get_param(model_name,'FileName')).getCanonicalPath());
        assert(strcmpi(actual,requested), ...
            'A same-name model from another directory is already loaded.');
    else
        load_system(requested);
    end
    loaded_path=char(java.io.File(get_param(model_name,'FileName')).getCanonicalPath());
    assert(strcmpi(loaded_path,requested),'Loaded model path differs from the requested file.');
end

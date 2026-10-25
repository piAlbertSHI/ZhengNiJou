function state=HeatDriveECC_ObserverContext(action,model,varargin)
% Process-local output routing only: never a physical state or model parameter.
    persistent contexts
    if isempty(contexts),contexts=containers.Map('KeyType','char','ValueType','any');end
    if isnumeric(model),model=get_param(model,'Name');end
    model=char(model);assert(isvarname(model));
    switch action
        case 'register'
            if isKey(contexts,model)
                prior=contexts(model);assert(prior.terminated,'Observer context is still active.');
            end
            target=char(java.io.File(varargin{1}).getCanonicalPath());
            assert(isfolder(fileparts(target)) && ~isfile(target) && ~isfile([target 'l']), ...
                'Require an existing output folder and fresh observer evidence.');
            state=struct('model',model,'process_pid',feature('getpid'), ...
                'path',target,'run_id',char(java.util.UUID.randomUUID()), ...
                'started',false,'terminated',false,'last_time',-Inf, ...
                'sample_count',0,'clock',[]);
            contexts(model)=state;
        case 'get'
            assert(isKey(contexts,model),'No process-local observer context registered.');
            state=contexts(model);assert(state.process_pid==feature('getpid'));
        case 'put'
            assert(isKey(contexts,model));old=contexts(model);state=varargin{1};
            assert(strcmp(state.path,old.path) && strcmp(state.run_id,old.run_id) && ...
                state.process_pid==old.process_pid && strcmp(state.model,old.model), ...
                'Do not rebind an active observation destination.');
            contexts(model)=state;
        case 'clear'
            if isKey(contexts,model),remove(contexts,model);end
            state=[];
        otherwise
            error('Unknown observer context action.');
    end
end

function record=Install_HeatDriveECC_HorizonCommands(model,commands,proof,which_case,runtime_options)
% Commands are external inputs, not a transformation of the saved Operating Point.
    assert(any(strcmp(which_case,{'reference','extended'})));workspace=get_param(model,'ModelWorkspace');
    assignin('base','EIGHTH_ROUND_OPTIONS',runtime_options);
    rows=proof.commands;if isstruct(rows),rows=num2cell(rows);end
    for k=1:numel(rows)
        row=rows{k};value=commands.(row.variable);
        if row.model_workspace,assignin(workspace,row.variable,value);else,assignin('base',row.variable,value);end
        for suffix={'_time_s','_values'}
            name=[row.variable suffix{1}];
            if strcmp(suffix{1},'_time_s'),v=value.Time;else,v=value.Data;end
            if hasVariable(workspace,name),assignin(workspace,name,v);
            elseif evalin('base',sprintf('exist(''%s'',''var'')',name)),assignin('base',name,v);end
        end
    end
    record=Check_HeatDriveECC_HorizonBindings(commands,proof,which_case,runtime_options);
end

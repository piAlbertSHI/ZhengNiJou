function record = Test_HeatDriveECC_NativeLogHistoryParameterType(output_file)
% Isolated thermal-mass API fixture; no coupled state or repository model is loaded.
    model='HeatDriveECC_native_log_parameter_type_fixture';assert(~bdIsLoaded(model));
    new_system(model);cleanup=onCleanup(@() bdclose(model));
    load_system('nesl_utility');load_system('fl_lib');
    add_block('nesl_utility/Solver Configuration',[model '/Solver']);
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass',[model '/Mass']);
    solver=get_param([model '/Solver'],'PortHandles');mass=get_param([model '/Mass'],'PortHandles');
    a=[solver.LConn solver.RConn];b=[mass.LConn mass.RConn];assert(numel(a)==1 && numel(b)==1);
    add_line(model,a,b);
    parameter_type=class(get_param(model,'SimscapeLogDataHistory'));
    input=Simulink.SimulationInput(model).setModelParameter('CaptureErrors','on','StopTime','0.001');
    text_result=sim(input.setModelParameter('SimscapeLogDataHistory','20002'));
    numeric_result=sim(input.setModelParameter('SimscapeLogDataHistory',20002));
    record=struct('schema','heatdrive_ecc_native_history_API_type_fixture_v1', ...
        'actual_parameter_class',parameter_type,'text_argument_error',text_result.ErrorMessage, ...
        'numeric_argument_error',numeric_result.ErrorMessage, ...
        'numeric_scalar_argument_pass',isempty(numeric_result.ErrorMessage), ...
        'api_fixture_network','isolated thermal mass and solver configuration', ...
        'api_fixture_sim_calls',2,'coupled_physics_simulated',false,'coupled_operating_point_loaded',false);
    fprintf('%s\n',jsonencode(record));
    if nargin==1
        assert(~isfile(output_file),'Never overwrite API type evidence.');
        fid=fopen(output_file,'w','n','UTF-8');assert(fid>=0);
        file_cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    end
    assert(~isempty(text_result.ErrorMessage) && isempty(numeric_result.ErrorMessage), ...
        'The logging-API type diagnosis is not confirmed.');
end

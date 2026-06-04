function batch_result = Run_GlobalXi_Unloading_Prototype(options)
% Run the accepted GlobalXi adiabatic unloading module from a loading checkpoint.
    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    options = apply_defaults(options);
    batch_result = GlobalXi_TimeStep_Core('unloading', options);
end

function options = apply_defaults(options)
    options.N = get_field(options, 'N', 51);
    options.Nt = get_field(options, 'Nt', 960);
    options.Nt_unload = get_field(options, 'Nt_unload', options.Nt);
    options.Tr = get_field(options, 'Tr', 293);
    options.Hfor = get_field(options, 'Hfor', 1.1e6);
    options.Pmax = get_field(options, 'Pmax', 0.59e6);
    options.T_load = get_field(options, 'T_load', 0.1);
    options.T_unload = get_field(options, 'T_unload', 0.1);
    options.ds0 = get_field(options, 'ds0', -35);
    options.hc = get_field(options, 'hc', 0);
end

function value = get_field(s, name, default_value)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default_value;
    end
end

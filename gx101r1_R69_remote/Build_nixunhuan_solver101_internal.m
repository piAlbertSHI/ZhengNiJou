function target_model_path = Build_nixunhuan_solver101_internal(force_rebuild, build_overrides)
% Build the optional Simulink-internal 101-node exchanger model.

    if nargin < 1 || isempty(force_rebuild)
        force_rebuild = false;
    end
    if nargin < 2 || isempty(build_overrides)
        build_overrides = struct();
    end

    this_dir = fileparts(mfilename('fullpath'));
    build_options = struct( ...
        'target_model_path', fullfile(this_dir, 'nixunhuan_solver101_internal.slx'), ...
        'target_model_name', 'nixunhuan_solver101_internal', ...
        'sma_node_count', 101, ...
        'sma_tap_count', 101, ...
        'sma_interface_mode', 'dual_path_serial_nodewise', ...
        'temperature_workspace_var', 'Tx101_internal', ...
        'temperature_init_expr_template', 'solver_T_init_101_internal(%d)', ...
        'compact_visual_font_size', 5, ...
        'root_manifold_split_mode', 'none');

    if isstruct(build_overrides)
        override_names = fieldnames(build_overrides);
        for idx = 1:numel(override_names)
            build_options.(override_names{idx}) = build_overrides.(override_names{idx});
        end
    end

    target_model_path = Build_Simulink_Exchange_Model(force_rebuild, build_options);
end

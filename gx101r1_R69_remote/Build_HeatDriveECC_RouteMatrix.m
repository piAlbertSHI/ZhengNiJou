function routes = Build_HeatDriveECC_RouteMatrix(schedule)
% Build valve and route matrix for SHEX/HHEX/CHEX full-cycle operation.

    names = schedule.stage_names;
    routes = repmat(base_route(), numel(names), 1);
    for idx = 1:numel(names)
        route = base_route();
        route.stage_id = idx;
        route.stage_name = names{idx};
        route.route_id = idx;
        switch names{idx}
            case 'sma_heat_load'
                route.SHEX_to_SMA = 1;
                route.SMA_loop_pump_on = 1;
                route.mechanical_coupling_active = 1;
                route.three_way_valve_1_position = 1;
                route.three_way_valve_2_position = 0;
                route.check_valve_states = [1 0 0 0];
            case 'se_reject_heat'
                route.SE_to_THE = 1;
                route.SE_loop_pump_on = 1;
                route.mechanical_coupling_active = 0;
                route.three_way_valve_1_position = 0;
                route.three_way_valve_2_position = 1;
                route.check_valve_states = [0 0 1 0];
            case 'sma_cool_unload'
                route.THE_to_SMA = 1;
                route.SMA_loop_pump_on = 1;
                route.mechanical_coupling_active = 1;
                route.three_way_valve_1_position = 2;
                route.three_way_valve_2_position = 0;
                route.check_valve_states = [0 1 0 0];
            case 'se_absorb_heat'
                route.CHEX_to_SE = 1;
                route.SE_loop_pump_on = 1;
                route.mechanical_coupling_active = 0;
                route.three_way_valve_1_position = 0;
                route.three_way_valve_2_position = 2;
                route.check_valve_states = [0 0 0 1];
        end
        routes(idx) = route;
    end
end

function route = base_route()
    route = struct();
    route.stage_id = 0;
    route.stage_name = '';
    route.route_id = 0;
    route.SHEX_to_SMA = 0;
    route.THE_to_SMA = 0;
    route.SE_to_THE = 0;
    route.CHEX_to_SE = 0;
    route.SMA_loop_pump_on = 0;
    route.SE_loop_pump_on = 0;
    route.mechanical_coupling_active = 0;
    route.three_way_valve_1_position = 0;
    route.three_way_valve_2_position = 0;
    route.check_valve_states = [0 0 0 0];
end

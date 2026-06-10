function result = Run_HeatDriveECC_FifthRound_Cycles(options)
% Run the mature-loop fifth-round Simulink model and audit physical probes.

    if nargin < 1 || isempty(options)
        options = Build_HeatDriveECC_FifthRound_Defaults();
    else
        options = Build_HeatDriveECC_FifthRound_Defaults(options);
    end
    if ~isfolder(options.outputs_dir)
        mkdir(options.outputs_dir);
    end
    Build_HeatDriveECC_Reconfigured_Model(options.force_rebuild_model);
    [params, schedule] = Build_HeatDriveECC_FifthRound_SimParams(options);

    sim_in = Simulink.SimulationInput(options.model_name);
    names = fieldnames(params);
    for idx = 1:numel(names)
        sim_in = sim_in.setVariable(names{idx}, params.(names{idx}));
    end
    sim_in = sim_in.setModelParameter('StopTime', sprintf('%.15g', schedule.total_time_s), ...
        'ReturnWorkspaceOutputs', 'on', 'SimscapeLogType', 'none');
    sim_out = sim(sim_in);

    signals = collect_signals(sim_out);
    [stage_table, cycle_table] = build_energy_tables(signals, options, schedule);
    result = struct('schema_version','heatdrive_ecc_fifth_round_result_v1', ...
        'options',options,'schedule',schedule,'signals',signals, ...
        'stage_energy_table',stage_table,'cycle_energy_table',cycle_table, ...
        'model_name',options.model_name,'model_path',options.model_path, ...
        'outputs_dir',options.outputs_dir);
    result.result_mat_path = fullfile(options.outputs_dir, 'fifth_round_run_result.mat');
    result.stage_energy_csv_path = fullfile(options.outputs_dir, 'fifth_round_stage_energy.csv');
    result.cycle_energy_csv_path = fullfile(options.outputs_dir, 'fifth_round_cycle_energy.csv');
    save(result.result_mat_path, 'result', '-v7.3');
    writetable(stage_table, result.stage_energy_csv_path);
    writetable(cycle_table, result.cycle_energy_csv_path);
    write_plots(signals, options, schedule);
end

function signals = collect_signals(sim_out)
    aliases = struct( ...
        'stage','fifth_stage_id_log', ...
        'mechanical','fifth_mechanical_audit', ...
        'Ta','sma_loop_sma_actuator_T_nodes_51', ...
        'Tr','se_loop_se_refrigerant_T_nodes_51', ...
        'sma_mdot_hold','sma_loop_mass_flow_v1_cold_inlet_kgps', ...
        'sma_mdot_cool','sma_loop_mass_flow_v4_hot_inlet_kgps', ...
        'se_mdot_hold','se_loop_mass_flow_v1_cold_inlet_kgps', ...
        'se_mdot_cool','se_loop_mass_flow_v4_hot_inlet_kgps', ...
        'sma_hold_in','sma_loop_sma_hold_inlet_fluid_temp_out', ...
        'sma_hold_out','sma_loop_sma_hold_outlet_fluid_temp_out', ...
        'sma_cool_in','sma_loop_sma_cooldown_inlet_fluid_temp_out', ...
        'sma_cool_out','sma_loop_sma_cooldown_outlet_fluid_temp_out', ...
        'se_hold_in','se_loop_sma_hold_inlet_fluid_temp_out', ...
        'se_hold_out','se_loop_sma_hold_outlet_fluid_temp_out', ...
        'se_cool_in','se_loop_sma_cooldown_inlet_fluid_temp_out', ...
        'se_cool_out','se_loop_sma_cooldown_outlet_fluid_temp_out');
    signals = struct();
    keys = fieldnames(aliases);
    for idx = 1:numel(keys)
        raw = sim_out.get(aliases.(keys{idx}));
        signals.(keys{idx}) = struct('time_s',raw.time(:), ...
            'values',squeeze(raw.signals.values));
    end
end

function [stage_table, cycle_table] = build_energy_tables(s, options, schedule)
    t = s.mechanical.time_s;
    mech = as_rows(s.mechanical.values, numel(t));
    stage_id = round(interp_series(s.stage, t));
    Ta = as_rows(interp_matrix(s.Ta, t), numel(t));
    Tr = as_rows(interp_matrix(s.Tr, t), numel(t));
    cp_f = options.system.cp_fluid_J_per_kgK;
    q_sma_hold = abs(interp_series(s.sma_mdot_hold,t))*cp_f .* ...
        (interp_series(s.sma_hold_in,t)-interp_series(s.sma_hold_out,t));
    q_sma_cool = abs(interp_series(s.sma_mdot_cool,t))*cp_f .* ...
        (interp_series(s.sma_cool_in,t)-interp_series(s.sma_cool_out,t));
    q_se_hold = abs(interp_series(s.se_mdot_hold,t))*cp_f .* ...
        (interp_series(s.se_hold_in,t)-interp_series(s.se_hold_out,t));
    q_se_cool = abs(interp_series(s.se_mdot_cool,t))*cp_f .* ...
        (interp_series(s.se_cool_in,t)-interp_series(s.se_cool_out,t));
    if isfield(s, 'sma_shex_heat')
        q_shex = interp_series(s.sma_shex_heat, t);
    else
        q_shex = zeros(size(t));
    end

    ma = options.material.rho_kg_per_m3*options.geometry.S_a_m2*options.geometry.L_a_m;
    mr = options.material.rho_kg_per_m3*options.geometry.S_r_m2*options.geometry.L_r_m;
    cp_s = options.material.cp_J_per_kgK;
    total_rows = options.cycle_count*4;
    rows = repmat(empty_stage(), total_rows, 1);
    for cycle_idx = 1:options.cycle_count
        for sid = 1:4
            row = (cycle_idx-1)*4+sid;
            t0 = schedule.time_s(row);
            t1 = schedule.time_s(row+1);
            mask = t >= t0 & t <= t1 & stage_id == sid;
            ii = find(mask);
            r = empty_stage();
            r.cycle_index=cycle_idx; r.stage_id=sid; r.stage_name=options.stage_names{sid};
            r.start_time_s=t0; r.end_time_s=t1; r.sample_count=numel(ii);
            if numel(ii) >= 2
                r.Ta_start_K=mean(Ta(ii(1),:)); r.Ta_end_K=mean(Ta(ii(end),:));
                r.Tr_start_K=mean(Tr(ii(1),:)); r.Tr_end_K=mean(Tr(ii(end),:));
                r.xMa_start=mech(ii(1),5); r.xMa_end=mech(ii(end),5);
                r.xMr_start=mech(ii(1),6); r.xMr_end=mech(ii(end),6);
                r.max_eq6_scaled=max(abs(mech(ii,7))); r.max_eq7_scaled=max(abs(mech(ii,8)));
                r.sma_fluid_energy_J=trapz(t(ii), select_stage_q(sid,q_sma_hold,q_sma_cool,ii));
                r.sma_shex_energy_J=trapz(t(ii), q_shex(ii));
                r.se_fluid_energy_J=trapz(t(ii), select_stage_q(sid,q_se_hold,q_se_cool,ii));
                r.sma_phase_mech_energy_J=trapz(t(ii),mech(ii,9));
                r.se_phase_mech_energy_J=trapz(t(ii),mech(ii,10));
                r.sma_sensible_change_J=ma*cp_s*(r.Ta_end_K-r.Ta_start_K);
                r.se_sensible_change_J=mr*cp_s*(r.Tr_end_K-r.Tr_start_K);
                r.sma_energy_residual_J=r.sma_sensible_change_J-r.sma_fluid_energy_J-r.sma_phase_mech_energy_J;
                r.se_energy_residual_J=r.se_sensible_change_J-r.se_fluid_energy_J-r.se_phase_mech_energy_J;
                r.sma_relative_residual=abs(r.sma_energy_residual_J)/max(sum(abs([r.sma_sensible_change_J,r.sma_fluid_energy_J,r.sma_phase_mech_energy_J])),1e-9);
                r.se_relative_residual=abs(r.se_energy_residual_J)/max(sum(abs([r.se_sensible_change_J,r.se_fluid_energy_J,r.se_phase_mech_energy_J])),1e-9);
            end
            rows(row)=r;
        end
    end
    stage_table=struct2table(rows);
    cycles=repmat(struct('cycle_index',0,'SHEX_input_J',0,'HHEX_reject_J',0, ...
        'CHEX_cooling_J',0,'system_residual_J',0,'relative_residual',0, ...
        'Qr_dynamic_W',0,'PECC_dynamic_W',0,'etaECC_dynamic',0),options.cycle_count,1);
    for c=1:options.cycle_count
        rr=rows([rows.cycle_index]==c);
        cycles(c).cycle_index=c;
        cycles(c).SHEX_input_J=rr(1).sma_shex_energy_J;
        cycles(c).HHEX_reject_J=-(rr(2).se_fluid_energy_J+rr(3).sma_fluid_energy_J);
        cycles(c).CHEX_cooling_J=rr(4).se_fluid_energy_J;
        cycles(c).system_residual_J=sum([rr.sma_energy_residual_J])+sum([rr.se_energy_residual_J]);
        scale=sum(abs([rr.sma_sensible_change_J]))+sum(abs([rr.se_sensible_change_J]))+1e-9;
        cycles(c).relative_residual=abs(cycles(c).system_residual_J)/scale;
        tau=sum(options.stage_max_duration_s);
        cycles(c).Qr_dynamic_W=cycles(c).CHEX_cooling_J/tau;
        cycles(c).PECC_dynamic_W=cycles(c).Qr_dynamic_W;
        cycles(c).etaECC_dynamic=cycles(c).PECC_dynamic_W/(1000*(15.57/(0.1731*1000)));
    end
    cycle_table=struct2table(cycles);
end

function q = select_stage_q(sid, q_hold, q_cool, ii)
    if sid==1 || sid==2, q=q_hold(ii); else, q=q_cool(ii); end
end

function r=empty_stage()
    r=struct('cycle_index',0,'stage_id',0,'stage_name','','start_time_s',0,'end_time_s',0,'sample_count',0, ...
        'Ta_start_K',NaN,'Ta_end_K',NaN,'Tr_start_K',NaN,'Tr_end_K',NaN, ...
        'xMa_start',NaN,'xMa_end',NaN,'xMr_start',NaN,'xMr_end',NaN, ...
        'max_eq6_scaled',NaN,'max_eq7_scaled',NaN,'sma_fluid_energy_J',NaN,'se_fluid_energy_J',NaN, ...
        'sma_shex_energy_J',NaN, ...
        'sma_phase_mech_energy_J',NaN,'se_phase_mech_energy_J',NaN, ...
        'sma_sensible_change_J',NaN,'se_sensible_change_J',NaN, ...
        'sma_energy_residual_J',NaN,'se_energy_residual_J',NaN, ...
        'sma_relative_residual',NaN,'se_relative_residual',NaN);
end

function v=interp_series(s,t)
    x=s.values(:); v=interp1(s.time_s,x,t,'linear','extrap');
end
function v=interp_matrix(s,t)
    x=as_rows(s.values,numel(s.time_s)); v=interp1(s.time_s,x,t,'linear','extrap');
end
function x=as_rows(x,n)
    x=squeeze(x); if size(x,1)~=n && size(x,2)==n, x=x.'; end
end

function write_plots(s, options, schedule)
    fig=figure('Visible','off','Color','w','Position',[100 100 1100 720]);
    subplot(2,1,1); plot(s.Ta.time_s,mean(as_rows(s.Ta.values,numel(s.Ta.time_s)),2),'r-', ...
        s.Tr.time_s,mean(as_rows(s.Tr.values,numel(s.Tr.time_s)),2),'b-'); grid on; ylabel('K'); legend('SMA','SE');
    subplot(2,1,2); m=as_rows(s.mechanical.values,numel(s.mechanical.time_s)); plot(s.mechanical.time_s,m(:,5:6)); grid on; ylabel('xM'); xlabel('s'); legend('SMA','SE');
    saveas(fig,fullfile(options.outputs_dir,'fifth_round_temperature_phase.png')); close(fig);
    schedule=schedule; %#ok<NASGU>
end

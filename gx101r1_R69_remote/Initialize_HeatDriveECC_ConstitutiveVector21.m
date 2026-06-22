function x0 = Initialize_HeatDriveECC_ConstitutiveVector21(options)
% Return the 21-node coupled SMA/SE constitutive state vector for Simulink.

    if nargin < 1 || isempty(options)
        options = Build_HeatDriveECC_EighthRound_Defaults();
    end
    if options.node_count ~= 21
        error('HeatDriveECC:ConstitutiveVectorNodeCount', ...
            'The Simulink constitutive vector interface expects 21 nodes.');
    end
    state = Initialize_HeatDriveECC_EighthRound_State(options);
    [state, ~] = HeatDriveECC_ConstitutiveCompatibilityStep51( ...
        state, options, 0.0, 1);
    x0 = pack_constitutive_state(state);
end

function x = pack_constitutive_state(state)
    fields = {'xM_a_21','xM_r_21','sigma_a_21','sigma_r_21', ...
        'epsilon_a_21','epsilon_r_21','pai_a_21','pai_r_21', ...
        'r_xi_a_21','r_xi_r_21'};
    parts = cell(numel(fields), 1);
    for idx = 1:numel(fields)
        parts{idx} = state.(fields{idx})(:);
    end
    x = vertcat(parts{:});
end

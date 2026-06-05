function result = PerovskiteECC_Constitutive(options, coupling)
% Build scalar constitutive states from paper Eq. 8-11.

    if nargin < 1 || isempty(options)
        options = Build_PerovskiteECC_Default_Options();
    end
    if nargin < 2 || isempty(coupling)
        coupling = PerovskiteECC_CouplingEquations(options);
    end

    sma = options.material.SMA;
    se = options.material.SE;

    result = struct();
    result.schema_version = 'perovskite_ecc_constitutive_eq8_11_v1';
    result.delta_xM_a = coupling.delta_xM_a;
    result.delta_xM_r = coupling.delta_xM_r;

    result.loading = build_state('loading', sma, se, ...
        coupling.sigma_a_ld_Pa, coupling.sigma_r_ld_Pa, coupling);
    result.unloading = build_state('unloading', sma, se, ...
        coupling.sigma_a_uld_Pa, coupling.sigma_r_uld_Pa, coupling);
end

function state = build_state(name, sma, se, sigma_a_Pa, sigma_r_Pa, coupling)
    epsilon_a = sma.epsilon_T * coupling.delta_xM_a - sigma_a_Pa / sma.E_m_Pa;
    epsilon_r = se.epsilon_T * coupling.delta_xM_r + sigma_r_Pa / se.E_m_Pa;

    state = struct();
    state.name = name;
    state.SMA = struct( ...
        'sigma_Pa', sigma_a_Pa, ...
        'epsilon', epsilon_a, ...
        'delta_xM', coupling.delta_xM_a);
    state.SE = struct( ...
        'sigma_Pa', sigma_r_Pa, ...
        'epsilon', epsilon_r, ...
        'delta_xM', coupling.delta_xM_r);
end


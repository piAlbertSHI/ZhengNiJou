function varargout = SMA_LocalKinetics(action, varargin)
% Shared local SMA constitutive helpers used by both global assembly and
% local return mapping. Keep these formulas as the single source of truth.

    switch lower(string(action))
        case "update_properties"
            varargout{1} = update_properties_impl(varargin{:});
        case "compliance_matrix"
            varargout{1} = compliance_matrix_impl(varargin{:});
        case "transformation_direction"
            varargout{1} = transformation_direction_impl(varargin{:});
        case "forward_transformation_residual_trial"
            varargout{1} = forward_transformation_residual_trial_impl(varargin{:});
        case "explicit_state_from_xi"
            varargout{1} = explicit_state_from_xi_impl(varargin{:});
        otherwise
            error('SMA_LocalKinetics:UnknownAction', 'Unknown action: %s', char(string(action)));
    end
end

function props = update_properties_impl(xi, params)
    xi = min(max(xi, 0.0), 1.0);
    xi_eff = min(max(xi, params.xi_floor), 1.0 - params.xi_floor);
    xi_eff_slope = double((xi >= params.xi_floor) && (xi <= 1.0 - params.xi_floor));
    E = params.E_A + xi_eff * (params.E_M - params.E_A);
    nu = params.nu;
    C_mat = (E / (1 - nu ^ 2)) * [1, nu, 0; nu, 1, 0; 0, 0, (1 - nu) / 2];

    props = struct();
    props.xi_eff = xi_eff;
    props.xi_eff_slope = xi_eff_slope;
    props.E = E;
    props.nu = nu;
    props.C_mat = C_mat;
    props.alpha = params.alpha_A + xi_eff * (params.alpha_M - params.alpha_A);
    props.alpha_vec = props.alpha * [1; 1; 0];
    props.c_eff = params.c_A + xi_eff * (params.c_M - params.c_A);
    props.k_eff = params.k_A + xi_eff * (params.k_M - params.k_A);
    props.rho = params.rho;
    props.A_eff = E * params.t_delta / (1 - nu ^ 2);
    props.D_eff = E * params.t_delta ^ 3 / (12 * (1 - nu ^ 2));
    props.dalpha_dxi = xi_eff_slope * (params.alpha_M - params.alpha_A);
    props.dc_eff_dxi = xi_eff_slope * (params.c_M - params.c_A);
    props.dk_eff_dxi = xi_eff_slope * (params.k_M - params.k_A);
end

function S_mat = compliance_matrix_impl(xi, params)
    props = update_properties_impl(xi, params);
    S_mat = props.C_mat \ eye(3);
end

function Lambda = transformation_direction_impl(sigma, H_max)
    sigma_eq = sqrt(max(sigma(1) ^ 2 - sigma(1) * sigma(2) + sigma(2) ^ 2 + 3 * sigma(3) ^ 2, 0.0));
    if sigma_eq < 1.0e-14
        Lambda = zeros(3, 1);
        return;
    end

    n_dir = [(2 * sigma(1) - sigma(2)) / (2 * sigma_eq); ...
             (2 * sigma(2) - sigma(1)) / (2 * sigma_eq); ...
             3 * sigma(3) / sigma_eq];
    Lambda = H_max * n_dir;
end

function residual = forward_transformation_residual_trial_impl(sigma, T, xi, Lambda, Delta_S, params)
    drive = sigma.' * Lambda + 0.5 * sigma.' * Delta_S * sigma + ...
            params.rho * params.ds0 * (T - params.M_s);
    residual = drive - params.Hfor * xi;
end

function state = explicit_state_from_xi_impl(eps, T, xi, xi_old, eps_tr_old, Lambda_hat, params)
    props = update_properties_impl(xi, params);
    eps_tr = eps_tr_old + (xi - xi_old) * Lambda_hat;
    eps_e = eps - eps_tr - props.alpha_vec * (T - params.Tr);
    sigma = props.C_mat * eps_e;

    state = struct();
    state.sigma = sigma;
    state.xi = xi;
    state.eps_tr = eps_tr;
    state.props = props;
end

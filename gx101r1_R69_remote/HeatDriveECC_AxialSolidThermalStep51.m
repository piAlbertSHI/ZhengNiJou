function [T_next, audit] = HeatDriveECC_AxialSolidThermalStep51( ...
        T_21, Q_to_solid_21_W, latent_21_W, mechanical_21_W, ...
        material, length_m, area_m2, k_W_per_mK, dt_s, options)
% Advance 21 solid temperature nodes with local heat, latent/mech, conduction.

    T_21 = T_21(:);
    Q_to_solid_21_W = Q_to_solid_21_W(:);
    latent_21_W = latent_21_W(:);
    mechanical_21_W = mechanical_21_W(:);
    N = numel(T_21);
    dx = length_m / N;
    mass_node = material.rho_kg_per_m3 * area_m2 * dx;
    C_node = mass_node * material.cp_J_per_kgK;
    conduction_W = zeros(N, 1);
    if options.solid.axial_conduction_enabled
        coeff = k_W_per_mK * area_m2 / dx;
        for idx = 1:N
            if idx > 1
                conduction_W(idx) = conduction_W(idx) + coeff * (T_21(idx - 1) - T_21(idx));
            end
            if idx < N
                conduction_W(idx) = conduction_W(idx) + coeff * (T_21(idx + 1) - T_21(idx));
            end
        end
    end
    net_W = Q_to_solid_21_W + conduction_W - latent_21_W - mechanical_21_W;
    T_next = T_21 + net_W .* dt_s ./ max(C_node, eps);

    audit = struct();
    audit.mass_node_kg = mass_node;
    audit.C_node_J_per_K = C_node;
    audit.Q_to_solid_W = sum(Q_to_solid_21_W);
    audit.latent_W = sum(latent_21_W);
    audit.mechanical_W = sum(mechanical_21_W);
    audit.conduction_W = sum(conduction_W);
    audit.sensible_W = sum(C_node .* (T_next - T_21) ./ max(dt_s, eps));
    audit.energy_residual_W = audit.Q_to_solid_W + audit.conduction_W - ...
        audit.latent_W - audit.mechanical_W - audit.sensible_W;
    audit.conduction_21_W = conduction_W;
    audit.net_21_W = net_W;
    audit.conduction_51_W = audit.conduction_21_W;
    audit.net_51_W = audit.net_21_W;
end

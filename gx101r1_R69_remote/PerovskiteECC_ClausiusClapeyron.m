function result = PerovskiteECC_ClausiusClapeyron(material, branch, temperature_K, delta_xM)
% Evaluate the Clausius-Clapeyron stress relation used by paper Eq. 12-14.

    if nargin < 4
        delta_xM = 0.0;
    end

    switch lower(strtrim(branch))
        case {'loading', 'ld', 'austenite_loading', 'actuator_loading'}
            slope = material.C_M_Pa_per_K;
            reference_K = material.T_As_K + delta_xM .* ...
                (material.T_Af_K - material.T_As_K);
            relation = 'C_M*(T - T_As - Delta_xM*(T_Af-T_As))';
        case {'unloading', 'uld', 'martensite_unloading', 'actuator_unloading'}
            slope = material.C_A_Pa_per_K;
            reference_K = material.T_Ms_K + delta_xM .* ...
                (material.T_Mf_K - material.T_Ms_K);
            relation = 'C_A*(T - T_Ms - Delta_xM*(T_Mf-T_Ms))';
        otherwise
            error('PerovskiteECC_ClausiusClapeyron:InvalidBranch', ...
                'Unknown Clausius-Clapeyron branch: %s', branch);
    end

    result = struct();
    result.branch = branch;
    result.relation = relation;
    result.temperature_K = temperature_K;
    result.delta_xM = delta_xM;
    result.slope_Pa_per_K = slope;
    result.reference_K = reference_K;
    result.sigma_Pa = slope .* (temperature_K - reference_K);
end


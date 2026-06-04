function plot_info = Plot_GX101R1_Probe_Timeseries_Individual(run_result, figures_dir, plot_info)
% Backward-compatible wrapper. The current implementation plots fixed probes
% as one continuous global-time curve rather than separate Cn-S2/Cn-S4 lines.

    if nargin < 2
        figures_dir = [];
    end
    if nargin < 3
        plot_info = struct();
    end
    plot_info = Plot_GX101R1_Fixed_Probe_Trajectories(run_result, figures_dir, plot_info);
end

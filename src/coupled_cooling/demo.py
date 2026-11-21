"""Run a compact four-stage cycle with synthetic, fully specified inputs."""

import argparse
import json

import numpy as np

from . import CaloricFluid, FixedColdCaloricCycle
from .transport import bs3_step


STAGES_S = (3.5, 1.5, 3.5, 1.5)


def demo_model():
    n = 5
    ambient_K, cold_K = 303.15, 298.15
    bed = dict(nodes=n, area_m2=2e-5, length_m=.18, fixed_mass_kg=.004,
               surface_m2=.02, Dh_m=.0032, solid_area_m2=2e-5)
    exchanger = dict(nodes=1, area_m2=2e-5, length_m=.12, fixed_mass_kg=.003, UA_W_K=5.)
    material = dict(cp_J_per_kgK=480., k_W_per_mK=12., E_m_Pa=35e9,
                    epsilon_T=.035, C_A_Pa_per_K=6e6, C_M_Pa_per_K=6e6,
                    Delta_h_J_per_kg=10000.)
    components = {
        "bed_a": dict(bed, fluid="SMA"),
        "bed_r": dict(bed, fluid="SE"),
        "shex": dict(exchanger, fluid="SMA", bus_index=0),
        "hhex_a": dict(exchanger, fluid="SMA", bus_index=1),
        "hhex_r": dict(exchanger, fluid="SE", bus_index=1),
        "chex": dict(exchanger, fluid="SE", bus_index=2),
    }
    config = dict(
        nodes=n, fluid_components=components, stage_durations_s=STAGES_S,
        geometry=dict(S_a_m2=2e-5, S_r_m2=2e-5, L_a_m=.18, L_r_m=.18),
        materials=dict(SMA=dict(material,T_Ms_K=292.,T_As_K=325.),
                       SE=dict(material,T_Ms_K=288.,T_As_K=301.)),
        solid_mass_kg=dict(SMA=.029, SE=.029),
        kinetics=dict(rate_a_to_A_1_per_s=1.8, rate_a_to_M_1_per_s=1.8,
                      rate_r_load_1_per_s=1.8, rate_r_stage3_unload_1_per_s=1.8,
                      drive_width_a_Pa=25e6, drive_width_r_Pa=25e6),
        mass_flow_kg_s=dict(SMA=.006, SE=.002),
        se_natural_h_W_m2K=12., bed_Nu=dict(SMA=3.66, SE=3.66),
        active_thermal_gate_G_W_K=dict(SMA=15., SE=15.),
        source_K=385., ambient_K=ambient_K, source_UA_W_K=20., ambient_UA_W_K=12.,
        chex_leak_UA_W_K=.05, cold_load_UA_W_K=.3, cold_load_W=2.,
        bus_capacity_J_K=[18., 23., 10., 15.],
        current_boundary_schema="heatdrive_ecc_current_caloric_boundary_v1",
        buffer_initial_masses_kg=[.03, .03, .03], buffer_auxiliary_capacity_J_K=[1., 1., 1.],
        water_buffer_role="adiabatic_one_port_side_compensator",
        water_chambers=[dict(fixed_mass_kg=.0015,initial_T_K=ambient_K) for _ in range(2)],
        advection_order=2, cold_boundary_mode="fixed_reservoir_temperature", cold_reservoir_K=cold_K,
        initial=dict(fluid_T_K={name:ambient_K for name in components},
                     solid_a_T_K=ambient_K, solid_r_T_K=ambient_K,
                     phase_a=1., phase_r=0., buffer_T_K=[ambient_K]*3,
                     bus_T_K=[ambient_K,ambient_K,cold_K,cold_K]),
    )
    t = [270., 300., 350., 420.]
    fluids = {
        "SMA": CaloricFluid(t, [4200.]*4, [.60]*4, 995.),
        "SE": CaloricFluid(t, [3700.]*4, [.45]*4, 1040.),
    }
    return FixedColdCaloricCycle(config, fluids)


def run(cycles=1, step_s=.02):
    if isinstance(cycles, bool) or not isinstance(cycles, int) or not 1 <= cycles <= 20:
        raise ValueError("Choose an integer cycle count from 1 to 20.")
    if not np.isfinite(step_s) or not .0005 <= step_s <= .05:
        raise ValueError("Choose a step between 0.0005 and 0.05 s.")
    ticks = [round(d / step_s) for d in STAGES_S]
    if not np.allclose(np.array(ticks) * step_s, STAGES_S, rtol=0, atol=1e-12):
        raise ValueError("The integration step must divide each stage exactly.")
    model = demo_model()
    initial = model.initial_state()
    state = initial.copy()
    time = 0.
    for _ in range(cycles):
        for stage, count in enumerate(ticks, 1):
            def rhs(_time, value):
                return model.evaluate(value, stage)[0]
            for _ in range(count):
                state = bs3_step(rhs, time, state, step_s)
                time += step_s
            model.unpack(state)
    end = model.unpack(state)
    reaction = float(state[model.slices["cold_reservoir_heat"]][0])
    return dict(case="synthetic_reference",cycles=cycles,duration_s=cycles*sum(STAGES_S),step_s=step_s,
                phase_fraction_mean=dict(SMA=float(end["xa"].mean()),SE=float(end["xr"].mean())),
                cold_reservoir_K=float(end["bus_T"][2]),cold_reservoir_reaction_J=reaction,
                **{name:float(value) for name,value in model.balance(state,initial).items()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cycles", type=int, default=1)
    parser.add_argument("--step-s", type=float, default=.02)
    args = parser.parse_args()
    try:
        result = run(args.cycles, args.step_s)
    except ValueError as error:
        parser.error(str(error))
    print(json.dumps(result, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()

"""Isolated constant-property conjugate bed, not a Qian whole-system solver.

Cell-average temperatures stay attached to fixed physical volumes. Shared face
fluxes telescope, including at reversal. Phase heat/mechanical work, pressure,
accessories and temperature-dependent properties are deliberately not modeled.
"""
from dataclasses import dataclass

import numpy as np
from scipy.sparse import csc_matrix
from scipy.sparse.linalg import expm_multiply


@dataclass(frozen=True)
class Bed:
    nodes: int
    length_m: float
    fluid_area_m2: float
    fluid_rho_kg_m3: float
    fluid_cp_J_kgK: float
    fluid_k_W_mK: float
    solid_area_m2: float
    solid_mass_kg: float
    solid_cp_J_kgK: float
    solid_k_W_mK: float
    UA_W_K: float
    periodic: bool = False
    advection_order: int = 2

    def __post_init__(self):
        positive = (self.length_m, self.fluid_area_m2, self.fluid_rho_kg_m3,
                    self.fluid_cp_J_kgK, self.solid_area_m2, self.solid_mass_kg,
                    self.solid_cp_J_kgK)
        nonnegative = (self.fluid_k_W_mK, self.solid_k_W_mK, self.UA_W_K)
        if (not isinstance(self.nodes, int) or isinstance(self.nodes, bool) or self.nodes < 3
                or not np.isfinite(positive + nonnegative).all() or min(positive) <= 0
                or min(nonnegative) < 0 or self.advection_order not in (1, 2)
                or not isinstance(self.periodic, bool)):
            raise ValueError("Require finite physical parameters and at least three cells")

    @property
    def dx(self):
        return self.length_m / self.nodes

    @property
    def fluid_mass(self):
        return self.fluid_rho_kg_m3 * self.fluid_area_m2 * self.length_m

    @property
    def fluid_capacity(self):
        return self.fluid_mass * self.fluid_cp_J_kgK / self.nodes

    @property
    def solid_capacity(self):
        return self.solid_mass_kg * self.solid_cp_J_kgK / self.nodes

    @property
    def state_size(self):
        return 2 * self.nodes + 1

    def energy(self, state):
        n = self.nodes
        return self.fluid_capacity * np.sum(state[:n]) + self.solid_capacity * np.sum(state[n:2*n])

    def fluxes(self, state, mdot, left_K, right_K):
        n = self.nodes
        fluid, solid = state[:n], state[n:2*n]
        advective = advective_faces(fluid, mdot * self.fluid_cp_J_kgK,
                                    left_K, right_K, self.periodic, self.advection_order)
        fluid_flux = advective + conductive_faces(fluid, self.fluid_k_W_mK * self.fluid_area_m2 / self.dx,
                                                   self.periodic)
        solid_flux = conductive_faces(solid, self.solid_k_W_mK * self.solid_area_m2 / self.dx,
                                        self.periodic)
        exchange = self.UA_W_K / n * (solid - fluid)
        return fluid_flux, solid_flux, exchange

    def rhs(self, state, mdot, left_K=0., right_K=0., fluid_power=None, solid_power=None):
        """Temperatures/boundaries are deviations from the same declared reference.

        Optional powers are cell-integrated W, used for manufactured-equation
        verification; they are absent from all physical sensible-bed trials.
        """
        n = self.nodes
        fluid_flux, solid_flux, exchange = self.fluxes(state, mdot, left_K, right_K)
        fluid_net = fluid_flux[:-1] - fluid_flux[1:] + exchange
        solid_net = solid_flux[:-1] - solid_flux[1:] - exchange
        external = 0.
        if fluid_power is not None:
            fluid_net = fluid_net + fluid_power
            external += np.sum(fluid_power)
        if solid_power is not None:
            solid_net = solid_net + solid_power
            external += np.sum(solid_power)
        # The last coordinate integrates only external boundary/source energy.
        boundary = fluid_flux[0] - fluid_flux[-1] + solid_flux[0] - solid_flux[-1] + external
        return np.r_[fluid_net / self.fluid_capacity, solid_net / self.solid_capacity, boundary]


def advective_faces(temperature, capacity_flow_W_K, left_K, right_K, periodic=False, order=2):
    """Face j points right, independent of actual flow sign; output has N+1 entries.

    For positive flow, interior Tface=1.5*Tup-0.5*Tupstream. At the first
    cell only, the backward slope uses the boundary face at half-cell distance:
    Tghost=2*Tin-Tfirst. Outlet uses the interior one-sided reconstruction.
    Negative flow mirrors this flux evaluation, never the stored state itself.
    No limiter/clipping is applied: a discontinuous front can overshoot.
    """
    temperature = np.asarray(temperature)
    if capacity_flow_W_K == 0:
        return np.zeros(len(temperature) + 1)
    if capacity_flow_W_K < 0:
        return -advective_faces(temperature[::-1], -capacity_flow_W_K,
                                right_K, left_K, periodic, order)[::-1]
    if periodic:
        right_faces = temperature.copy()
        if order == 2:
            right_faces += .5 * (temperature - np.roll(temperature, 1))
        faces = np.r_[right_faces[-1], right_faces]
    else:
        right_faces = temperature.copy()
        if order == 2:
            upstream = np.r_[2 * left_K - temperature[0], temperature[:-1]]
            right_faces += .5 * (temperature - upstream)
        faces = np.r_[left_K, right_faces]
    return capacity_flow_W_K * faces


def conductive_faces(temperature, conductance_W_K, periodic=False):
    """Centered interior diffusion; periodic closure or insulated physical ends."""
    faces = np.zeros(len(temperature) + 1)
    faces[1:-1] = -conductance_W_K * np.diff(temperature)
    if periodic:
        faces[0] = faces[-1] = -conductance_W_K * (temperature[0] - temperature[-1])
    return faces


def bs3_step(rhs, time, state, dt):
    """Fixed-step Bogacki-Shampine third-order advance, no adaptive rejection.

    Stage coefficients match the third-order member underlying ode3/ode23.
    Kept explicit because the reference contract requires a fixed grid; SciPy's
    public RK23 solver is adaptive. Tests compare with its coefficient tableau.
    """
    k1 = rhs(time, state)
    k2 = rhs(time + .5 * dt, state + .5 * dt * k1)
    k3 = rhs(time + .75 * dt, state + .75 * dt * k2)
    return state + dt * (2*k1/9 + k2/3 + 4*k3/9)


def affine_exponential(rhs, initial, duration):
    """Independent time propagation of an affine, frozen-drive semidiscretization.

    This verifies time integration, not an independent physical operator.
    Augmentation handles constant boundary forcing without a matrix inverse.
    """
    size = len(initial)
    baseline = rhs(np.zeros(size))
    matrix = np.zeros((size + 1, size + 1))
    for j in range(size):
        unit = np.zeros(size)
        unit[j] = 1.
        matrix[:size, j] = rhs(unit) - baseline
    matrix[:size, -1] = baseline
    return expm_multiply(csc_matrix(matrix * duration), np.r_[initial, 1.])[:size]


def advance_segments(bed, segments, dt, sample_times, initial=None):
    """Run once on an aligned grid, retaining selected profiles, not checkpoints."""
    if not np.isfinite(dt) or dt <= 0:
        raise ValueError("Require a finite positive fixed step")
    times = np.asarray(sample_times, dtype=float)
    if (times.ndim != 1 or len(times) < 2 or times[0] != 0 or not np.isfinite(times).all()
            or np.any(np.diff(times) <= 0) or times[-1] != segments[-1]["end_s"]):
        raise ValueError("Require complete strictly increasing sample coordinates")
    indices = np.rint(times/dt).astype(int)
    ends = np.array([s["end_s"] for s in segments])
    if (not np.allclose(indices*dt, times, rtol=0, atol=1e-12)
            or np.any(np.diff(ends) <= 0) or not np.isfinite(ends).all()
            or not np.allclose(np.rint(ends/dt)*dt, ends, rtol=0, atol=1e-12)):
        raise ValueError("Events and observations must land on the actual fixed grid")
    if any(not np.isfinite([s[k] for k in ("mdot_kg_s", "left_K", "right_K")]).all() for s in segments):
        raise ValueError("Nonfinite boundary drive")
    state = np.zeros(bed.state_size) if initial is None else np.asarray(initial, dtype=float).copy()
    if state.shape != (bed.state_size,) or not np.isfinite(state).all():
        raise ValueError("Invalid initial state")
    initial_energy = bed.energy(state) - state[-1]
    samples = [state.copy()]
    wanted = set(indices[1:])
    prior_index = 0
    max_balance = 0.
    min_fluid, max_fluid = np.min(state[:bed.nodes]), np.max(state[:bed.nodes])
    transitions = []
    previous_end = None
    for segment in segments:
        start_state = state.copy()
        if previous_end is not None:
            transitions.append({"time_s": prior_index*dt,
                                "all_coordinates_bitwise_unchanged": bool(np.array_equal(start_state, previous_end))})
        rhs = lambda t, y: bed.rhs(y, segment["mdot_kg_s"], segment["left_K"], segment["right_K"])
        final_index = int(round(segment["end_s"]/dt))
        for index in range(prior_index, final_index):
            state = bs3_step(rhs, index*dt, state, dt)
            if not np.isfinite(state).all():
                raise FloatingPointError("Nonfinite state; do not propagate this experiment")
            max_balance = max(max_balance, abs(bed.energy(state) - state[-1] - initial_energy))
            min_fluid = min(min_fluid, float(np.min(state[:bed.nodes])))
            max_fluid = max(max_fluid, float(np.max(state[:bed.nodes])))
            if index + 1 in wanted:
                samples.append(state.copy())
        prior_index = final_index
        previous_end = state.copy()
    if len(samples) != len(times):
        raise RuntimeError("Incomplete sampled output")
    return np.asarray(samples), {"steps": prior_index, "max_abs_energy_residual_J": float(max_balance),
        "fluid_deviation_range_K_all_major_steps": [float(min_fluid), float(max_fluid)],
        "transitions": transitions, "state_reset_or_reindex_applied": False,
        "boundary_mass_net_kg_s": 0., "mass_basis": "constant density; equal signed mass flow on every face",
        "energy_basis": "sum(Cf*theta_f+Cs*theta_s)-integrated external boundary energy; BS3 stages",
        "saved_per_step_full_states": False, "checkpoint_saved": False}

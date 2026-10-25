"""BS3 embedded error control with compensated addition of accepted increments.

The compensation applies uniformly to ALL coordinates; it has no knowledge of
energy, phase, mass or a desired invariant. No physical projection/correction.
Rejected trials never consume the accepted-coordinate summation remainder.
SciPy supplies the BS3 tableau, error estimator and cubic dense interpolator.
"""
import numpy as np
from scipy.integrate import RK23


def compensated_add(state, increment, remainder):
    adjusted = increment-remainder
    total = state+adjusted
    return total, (total-state)-adjusted


class CompensatedBS3(RK23):
    def __init__(self, fun, t0, y0, t_bound, *, compensation=None, controlled_size=None, **kwargs):
        self.controlled_size = controlled_size
        self.initial_control_nfev = 0
        if controlled_size is not None:
            y0 = np.asarray(y0)
            if (not isinstance(controlled_size, int) or isinstance(controlled_size, bool)
                    or not 1 <= controlled_size <= len(y0) or kwargs.get("vectorized", False)):
                raise ValueError("Require a nonvectorized physical prefix for passive-suffix integration")
            if kwargs.get("first_step") is None:
                # Public RK23 initialization chooses the same step as the physical
                # system alone. The suffix MUST NOT feed back into that system.
                options = dict(kwargs)
                if np.ndim(options.get("atol", 1e-6)):
                    options["atol"] = np.asarray(options["atol"])[:controlled_size]
                probe = RK23(lambda t, v: fun(t, np.r_[v, y0[controlled_size:]])[:controlled_size],
                             t0, y0[:controlled_size], t_bound, **options)
                kwargs["first_step"] = probe.h_abs
                self.initial_control_nfev = probe.nfev
        super().__init__(fun, t0, y0, t_bound, **kwargs)
        self.compensation = np.zeros_like(self.y) if compensation is None else compensation.copy()
        if self.compensation.shape != self.y.shape or not np.isfinite(self.compensation).all():
            raise ValueError("Invalid numerical summation remainder")

    def _estimate_error_norm(self, K, h, scale):
        if self.controlled_size is None:
            return super()._estimate_error_norm(K, h, scale)
        physical = np.ascontiguousarray(K[:, :self.controlled_size])
        error = self._estimate_error(physical, h)/scale[:self.controlled_size]
        return np.linalg.norm(error)/np.sqrt(self.controlled_size)

    def _weighted_increment(self, K, weights, h):
        if self.controlled_size is None:
            return h*(K.T@weights)
        # Match the physical-only matrix shape/layout too: otherwise BLAS can
        # change rounding and hence future adaptive steps merely on observation.
        physical = np.ascontiguousarray(K[:, :self.controlled_size])
        return h*np.r_[physical.T@weights, K[:, self.controlled_size:].T@weights]

    def _step_impl(self):
        spacing = 10*abs(np.nextafter(self.t, self.direction*np.inf)-self.t)
        size = min(self.max_step, max(spacing, self.h_abs))
        rejected = False
        while True:
            if size < spacing:
                return False, self.TOO_SMALL_STEP
            end = self.t+self.direction*size
            if self.direction*(end-self.t_bound) > 0:
                end = self.t_bound
            h = end-self.t
            self.K[0] = self.f
            for index in range(1, self.n_stages):
                increment = self._weighted_increment(self.K[:index], self.A[index, :index], h)
                trial, _ = compensated_add(self.y, increment, self.compensation)
                self.K[index] = self.fun(self.t+self.C[index]*h, trial)
            increment = self._weighted_increment(self.K[:-1], self.B, h)
            candidate, remainder = compensated_add(self.y, increment, self.compensation)
            final_rate = self.fun(end, candidate)
            self.K[-1] = final_rate
            scale = self.atol+self.rtol*np.maximum(abs(self.y), abs(candidate))
            error = self._estimate_error_norm(self.K, h, scale)
            if not np.isfinite(error):
                return False, "Nonfinite BS3 embedded error estimate"
            factor = 10. if error == 0 else min(10., max(.2, .9*error**self.error_exponent))
            if error < 1:
                self.y_old, self.h_previous = self.y, h
                self.y, self.t, self.f = candidate, end, final_rate
                self.compensation = remainder
                self.h_abs = abs(h)*(min(1., factor) if rejected else factor)
                return True, None
            size = abs(h)*min(1., factor)
            rejected = True

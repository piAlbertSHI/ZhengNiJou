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
    def __init__(self, *args, compensation=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.compensation = np.zeros_like(self.y) if compensation is None else compensation.copy()
        if self.compensation.shape != self.y.shape or not np.isfinite(self.compensation).all():
            raise ValueError("Invalid numerical summation remainder")

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
                increment = h*(self.K[:index].T@self.A[index, :index])
                trial, _ = compensated_add(self.y, increment, self.compensation)
                self.K[index] = self.fun(self.t+self.C[index]*h, trial)
            increment = h*(self.K[:-1].T@self.B)
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

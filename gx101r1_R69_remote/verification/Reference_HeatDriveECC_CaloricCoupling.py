"""Independent incompressible caloric-cycle diagnostic, NOT a production OP.

Fixed rho_ref and integrated cp(T) are an explicit thermal-PDE approximation.
This is not the compressible rho/u branch, nor a proven Qian material model.
"""
import numpy as np

from Reference_HeatDriveECC_ConservativeTransport import advective_faces, conductive_faces


class CaloricFluid:
    def __init__(self, temperature, cp, conductivity, rho_ref, reference=303.15):
        self.t, self.cp, self.k = (np.array(v, dtype=float, copy=True) for v in
                                   (temperature, cp, conductivity))
        self.rho, self.reference = float(rho_ref), float(reference)
        if (self.t.ndim != 1 or len(self.t) < 2 or self.cp.shape != self.t.shape
                or self.k.shape != self.t.shape or not np.isfinite(np.r_[self.t, self.cp, self.k, self.rho, reference]).all()
                or np.any(np.diff(self.t) <= 0) or min(self.cp.min(), self.k.min(), self.rho) <= 0
                or not self.t[0] <= reference <= self.t[-1]):
            raise ValueError("Require positive finite caloric tables and an in-domain reference")
        self.slopes = np.diff(self.cp)/np.diff(self.t)
        self.h_knots = np.r_[0., np.cumsum(.5*(self.cp[:-1]+self.cp[1:])*np.diff(self.t))]
        self.offset = float(self._unreferenced_h(np.asarray(reference)))
        self.h_knots -= self.offset

    def _unreferenced_h(self, t):
        i = np.minimum(np.searchsorted(self.t, t, side="right")-1, len(self.t)-2)
        delta = t-self.t[i]
        return self.h_knots[i]+self.cp[i]*delta+.5*self.slopes[i]*delta**2

    def enthalpy(self, temperature):
        t = np.asarray(temperature)
        if not np.isfinite(t).all() or np.any(t < self.t[0]) or np.any(t > self.t[-1]):
            raise ValueError("Caloric temperature outside table; no clipping or extrapolation")
        # h_knots are already relative to the same reference.
        return self._unreferenced_h(t)

    def temperature(self, enthalpy):
        h = np.asarray(enthalpy)
        if not np.isfinite(h).all() or np.any(h < self.h_knots[0]) or np.any(h > self.h_knots[-1]):
            raise ValueError("Caloric energy outside table; no clipping or extrapolation")
        i = np.minimum(np.searchsorted(self.h_knots, h, side="right")-1, len(self.t)-2)
        dh = h-self.h_knots[i]
        delta = 2*dh/(self.cp[i]+np.sqrt(self.cp[i]**2+2*self.slopes[i]*dh))
        return self.t[i]+delta

    def conductivity(self, temperature):
        self.enthalpy(temperature)
        return np.interp(temperature, self.t, self.k)

    def contract(self):
        return {"temperature_K": self.t.tolist(), "cp_J_kgK": self.cp.tolist(),
                "conductivity_W_mK": self.k.tolist(), "fixed_density_kg_m3": self.rho,
                "reference_temperature_K": self.reference,
                "enthalpy_law": "exact integral of piecewise linear cp(T) at saved reference pressure",
                "compressible_EOS_equivalence_claim": False}


def compatibility(xa, xr, geometry, materials, rates=None):
    g, a, r = geometry, materials["SMA"], materials["SE"]
    ratio = g["S_r_m2"]/g["S_a_m2"]
    denominator = g["L_a_m"]*ratio/a["E_m_Pa"]+g["L_r_m"]/r["E_m_Pa"]
    sr = (g["L_a_m"]*a["epsilon_T"]*(1-np.mean(xa))
          - g["L_r_m"]*r["epsilon_T"]*np.mean(xr))/denominator
    sa = ratio*sr
    ea, er = a["epsilon_T"]*(1-xa)-sa/a["E_m_Pa"], r["epsilon_T"]*xr+sr/r["E_m_Pa"]
    result = {"sigma_a_Pa": sa, "sigma_r_Pa": sr,
              "epsilon_a": ea, "epsilon_r": er,
              "force_residual_N": sa*g["S_a_m2"]-sr*g["S_r_m2"],
              "displacement_residual_m": g["L_a_m"]*ea.mean()-g["L_r_m"]*er.mean()}
    if rates is not None:
        ra, rr = rates
        dsr = (-g["L_a_m"]*a["epsilon_T"]*ra.mean()-g["L_r_m"]*r["epsilon_T"]*rr.mean())/denominator
        dea = -a["epsilon_T"]*ra-ratio*dsr/a["E_m_Pa"]
        der = r["epsilon_T"]*rr+dsr/r["E_m_Pa"]
        result.update(mechanical_a_W=-sa*dea*g["S_a_m2"]*g["L_a_m"]/len(xa),
                      mechanical_r_W=sr*der*g["S_r_m2"]*g["L_r_m"]/len(xr),
                      displacement_rate_residual_m_s=g["L_a_m"]*dea.mean()-g["L_r_m"]*der.mean())
    return result


def reduced_phase_rates(ta, tr, xa, xr, mechanical, materials, kinetics, stage):
    """Port of the existing restricted reduced closure; no fitted Af/Mf invented."""
    if stage not in (1, 2, 3, 4):
        raise ValueError("Unknown physical stage")
    a, r, c = materials["SMA"], materials["SE"], kinetics
    sa, sr = mechanical["sigma_a_Pa"], mechanical["sigma_r_Pa"]
    surface_a = a["T_As_K"]+(a["T_Ms_K"]-a["T_As_K"])*xa
    surface_r = r["T_As_K"]+(r["T_Ms_K"]-r["T_As_K"])*xr
    if stage in (1, 2):
        da, dr = a["C_A_Pa_per_K"]*(ta-surface_a)-sa, sr-r["C_M_Pa_per_K"]*(tr-surface_r)
        ra = -c["rate_a_to_A_1_per_s"]*(-np.expm1(-np.maximum(da, 0)/c["drive_width_a_Pa"]))*xa
        rr = c["rate_r_load_1_per_s"]*(-np.expm1(-np.maximum(dr, 0)/c["drive_width_r_Pa"] ))*(1-xr)
    else:
        da, dr = sa-a["C_M_Pa_per_K"]*(ta-surface_a), r["C_A_Pa_per_K"]*(tr-surface_r)-sr
        ra = c["rate_a_to_M_1_per_s"]*(-np.expm1(-np.maximum(da, 0)/c["drive_width_a_Pa"] ))*(1-xa)
        rr = -c["rate_r_stage3_unload_1_per_s"]*(-np.expm1(-np.maximum(dr, 0)/c["drive_width_r_Pa"] ))*xr
    return ra, rr


class CaloricCycle:
    """Persistent two-bed, two-fluid network with finite accessory inventories.

    Graph is an explicit engineering diagnostic, not literal full-SLX equivalence.
    Water return -> selected SHEX/HHEX channel -> single SMA bed -> water return.
    Stage2: cold chamber -> reverse SE -> HHEX glycol -> hot chamber.
    Stage4: hot chamber -> forward SE -> CHEX glycol -> cold chamber.
    """
    LEDGERS = ("source", "ambient", "load", "latent_a", "latent_r", "mechanical_a", "mechanical_r", "chex")

    def __init__(self, contract, fluids):
        self.c, self.fluids = contract, fluids
        self.n = contract["nodes"]
        self.slices, self.masses, self.components = {}, {}, {}
        offset = 0
        for name, item in contract["fluid_components"].items():
            nodes = item["nodes"]
            self.slices[name] = slice(offset, offset+nodes)
            self.components[name] = item
            self.masses[name] = fluids[item["fluid"]].rho*item["area_m2"]*item["length_m"]/nodes
            offset += nodes
        for name, size in (("solid_a", self.n), ("solid_r", self.n), ("phase_a", self.n), ("phase_r", self.n),
                           ("buffer_H", 3), ("buffer_mass_change", 2), ("bus_E", 4), ("ledgers", len(self.LEDGERS))):
            self.slices[name] = slice(offset, offset+size)
            offset += size
        self.size = offset
        self.capacities = {m: contract["solid_mass_kg"][m]*contract["materials"][m]["cp_J_per_kgK"]/self.n
                           for m in ("SMA", "SE")}
        self.bus_capacity = np.asarray(contract["bus_capacity_J_K"])
        if (set(self.components) != {"bed_a", "bed_r", "shex", "hhex_a", "hhex_r", "chex"}
                or self.n < 3 or np.min(self.bus_capacity) <= 0):
            raise ValueError("Incomplete physical network")

    def initial_state(self):
        y = np.zeros(self.size)
        y[self.slices["phase_a"]] = 1.
        return y

    def unpack(self, y):
        if y.shape != (self.size,) or not np.isfinite(y).all():
            raise ValueError("Invalid coupled state")
        t, h = {}, {}
        for name, item in self.components.items():
            h[name] = y[self.slices[name]]/self.masses[name]
            t[name] = self.fluids[item["fluid"]].temperature(h[name])
        xa, xr = y[self.slices["phase_a"]], y[self.slices["phase_r"]]
        # This is an invalid-state rejection, not phase projection. Roundoff is
        # observed separately; no state or rate is clipped to pass this check.
        if min(xa.min(), xr.min()) < -1e-10 or max(xa.max(), xr.max()) > 1+1e-10:
            raise ValueError("Phase left its physical interval")
        m0 = self.c["buffer_initial_mass_kg"]
        masses = np.r_[m0, m0+y[self.slices["buffer_mass_change"]]]
        if masses.min() <= 0:
            raise ValueError("Piston chamber has exhausted fluid")
        bh = y[self.slices["buffer_H"]]/masses
        bt = np.array([self.fluids[k].temperature(v) for k, v in zip(("SMA", "SE", "SE"), bh)])
        return {"T": t, "h": h, "xa": xa, "xr": xr, "buffer_mass": masses, "buffer_h": bh,
                "buffer_T": bt, "Ta": 303.15+y[self.slices["solid_a"]]/self.capacities["SMA"],
                "Tr": 303.15+y[self.slices["solid_r"]]/self.capacities["SE"],
                "bus_T": 303.15+y[self.slices["bus_E"]]/self.bus_capacity}

    def evaluate(self, y, stage):
        if stage not in (1, 2, 3, 4):
            raise ValueError("Unknown stage")
        c, s, n = self.c, self.slices, self.n
        p = self.unpack(y)
        d = np.zeros_like(y)
        mechanical = compatibility(p["xa"], p["xr"], c["geometry"], c["materials"])
        rates = reduced_phase_rates(p["Ta"], p["Tr"], p["xa"], p["xr"], mechanical, c["materials"], c["kinetics"], stage)
        mechanical = compatibility(p["xa"], p["xr"], c["geometry"], c["materials"], rates)
        d[s["phase_a"]], d[s["phase_r"]] = rates
        bus_power = np.zeros(4)
        for name, item in self.components.items():
            tf = p["T"][name]
            k = self.fluids[item["fluid"]].conductivity(tf)
            dx = item["length_m"]/item["nodes"]
            conductance = 2*k[:-1]*k[1:]/(k[:-1]+k[1:])*item["area_m2"]/dx
            diff = conductive_faces(tf, conductance)
            d[s[name]] = diff[:-1]-diff[1:]
            if name in ("bed_a", "bed_r"):
                a = name == "bed_a"
                material, ts, solid = ("SMA", p["Ta"], "solid_a") if a else ("SE", p["Tr"], "solid_r")
                ua = (3.66*k*item["surface_m2"]/item["Dh_m"] if a or stage in (2, 4)
                      else np.full(n, c["se_natural_h_W_m2K"]*item["surface_m2"]))
                q = ua/n*(ts-tf)
                d[s[name]] += q
                sd = conductive_faces(ts, c["materials"][material]["k_W_per_mK"]*
                                      item["solid_area_m2"]/dx)
                d[s[solid]] = sd[:-1]-sd[1:]-q
            else:
                b = item["bus_index"]
                q = item["UA_W_K"]/item["nodes"]*(p["bus_T"][b]-tf)
                d[s[name]] += q
                bus_power[b] -= q.sum()
        latent = []
        for material, phase_rate, solid, work in (("SMA", rates[0], "solid_a", "mechanical_a_W"),
                                                  ("SE", rates[1], "solid_r", "mechanical_r_W")):
            q = c["solid_mass_kg"][material]/n*c["materials"][material]["Delta_h_J_per_kg"]*phase_rate
            d[s[solid]] += q+mechanical[work]
            latent.append(q.sum())

        def advect(name, flow, inlet_h):
            faces = advective_faces(p["h"][name], flow, inlet_h, inlet_h, order=2, limiter="MC")
            d[s[name]] += faces[:-1]-faces[1:]
            return faces[-1] if flow > 0 else -faces[0]

        # Returned powers, not cell temperatures, are shared at every interface.
        ma, mr = c["mass_flow_kg_s"]["SMA"], c["mass_flow_kg_s"]["SE"]
        water_hx = "shex" if stage in (1, 2) else "hhex_a"
        out = advect(water_hx, ma, p["buffer_h"][0])
        returned = advect("bed_a", ma if stage in (1, 2) else -ma, out/ma)
        d[s["buffer_H"]][0] += returned-ma*p["buffer_h"][0]
        if stage in (2, 4):
            donor, receiver, hx, flow = (2, 1, "hhex_r", -mr) if stage == 2 else (1, 2, "chex", mr)
            bed_out = advect("bed_r", flow, p["buffer_h"][donor])
            hx_out = advect(hx, mr, bed_out/mr)
            d[s["buffer_H"]][donor] -= mr*p["buffer_h"][donor]
            d[s["buffer_H"]][receiver] += hx_out
            d[s["buffer_mass_change"]][donor-1] -= mr
            d[s["buffer_mass_change"]][receiver-1] += mr
        qsource = c["source_UA_W_K"]*(c["source_K"]-p["bus_T"][0])
        qambient = c["ambient_UA_W_K"]*(c["ambient_K"]-p["bus_T"][1])
        qleak = c["chex_leak_UA_W_K"]*(c["ambient_K"]-p["bus_T"][2])
        qchex = c["cold_load_UA_W_K"]*(p["bus_T"][3]-p["bus_T"][2])
        bus_power += [qsource, qambient, qleak+qchex, c["cold_load_W"]-qchex]
        d[s["bus_E"]] = bus_power
        d[s["ledgers"]] = [qsource, qambient+qleak, c["cold_load_W"], *latent,
                            mechanical["mechanical_a_W"].sum(), mechanical["mechanical_r_W"].sum(), qchex]
        return d, p, mechanical

    def inventory_energy(self, y):
        s, c = self.slices, self.c
        sensible = sum(y[s[name]].sum() for name in self.components)
        sensible += sum(y[s[name]].sum() for name in ("solid_a", "solid_r", "buffer_H", "bus_E"))
        chemical = sum(-c["solid_mass_kg"][m]*c["materials"][m]["Delta_h_J_per_kg"]*
                       y[s[name]].mean() for m, name in (("SMA", "phase_a"), ("SE", "phase_r")))
        return sensible+chemical

    def balance(self, y, initial):
        ledger = y[self.slices["ledgers"]]
        return {"net_energy_residual_J": self.inventory_energy(y)-self.inventory_energy(initial)-ledger[:3].sum(),
                "SE_mass_residual_kg": y[self.slices["buffer_mass_change"]].sum(),
                "mechanical_exchange_residual_J": ledger[5]+ledger[6]}

# Agent2 Second-Round Paper and d_2 Extraction

Date: 2026-06-05

This note records the second-round source basis used by the `PerovskiteECC_*`
implementation. The first-round round-plate / GlobalXi / pressure-profile
route is intentionally treated only as a deprecated counterexample.

## Paper Model Scope

Source:

`热回收驱动弹热冷却系统/Elastocaloric cooler for waste heat recovery from perovskite solar cell with electricity and cooling production.pdf`

Implemented scope starts from Section 2.2, Elastocaloric cooler, and follows
Eq. 6-21 as a single-stage axial ECC model:

- 1D axial Ni-Ti SMA actuator and 1D axial Ni-Ti SE refrigerant.
- Geometry is represented by length `L` and cross-sectional area `S`.
- The default shape label is `generic_area`; no plate radius, rectangular
  width/thickness, or wire diameter is assumed by the paper-aligned main model.
- Default length discretization is 51 SMA nodes plus 51 SE nodes.

## Paper Defaults

Table 1 defaults:

- `S_r/S_a = 0.2`
- `L_r/L_a = 0.4`
- `T_c = 288 K`
- `T_0 = 308 K`
- `eta_hr = 0.7`
- Optional PSC audit defaults: `G = 1000 W/m^2`, `A_PSC = 0.01 m^2`

Table 2 defaults are converted to SI units in code:

- Refrigerant SE: `C_M = 7.3 MPa/K`, `C_A = 7.6 MPa/K`, `cp = 500 J/kg/K`,
  `Delta_h = 10000 J/kg`, `epsilon_T = 0.03`, `T_As = 268 K`,
  `T_Af = 288 K`, `T_Mf = 238 K`, `T_Ms = 258 K`, `w_uld = 4100 J/kg`,
  `w_ld = 5600 J/kg`, `E_m = 30 GPa`, `rho = 6500 kg/m^3`.
- Actuator SMA: `C_M = 7.3 MPa/K`, `C_A = 7.6 MPa/K`, `cp = 500 J/kg/K`,
  `Delta_h = 10000 J/kg`, `epsilon_T = 0.03`, `T_As = 323 K`,
  `T_Af = 343 K`, `T_Mf = 293 K`, `T_Ms = 313 K`, `E_m = 30 GPa`,
  `rho = 6500 kg/m^3`.

## d_2 Constitutive Ideas Migrated

`d_2.slx` contains eight MATLAB Function / Stateflow EMChart scripts. The
second-round model migrates the relevant ideas without copying its 12+12-node
hardcoding:

- Separate driver SMA and refrigerant SE node partitions.
- Persistent martensite fraction state concept `xi_state`.
- Driver SMA initializes martensitic; SE refrigerant initializes austenitic.
- SMA and SE share coupling stress through Eq. 6 and Eq. 7.
- Transformation driving force `pai` is kept as an auditable diagnostic.
- Transformation rate `r_xi` is computed in a d_2-like kernel, then bounded.
- Latent heat source `q_latent` is exposed per node.
- Pump and valve signals are emitted as stage-level controls.

The paper Eq. 6-21 algebra is the primary model. The d_2-inspired kernel is
used for node-level state diagnostics and extension points, not for imposing a
round-plate, pressure, or fixed 12+12 topology.


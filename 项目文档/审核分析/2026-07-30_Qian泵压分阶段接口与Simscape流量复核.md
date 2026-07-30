# Qian pressure interface and coupled Simscape audit

## Scope

This checkpoint uses the single canonical model:
`gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx`.

Qian 2019 Table 2/Table 4 targets are:

- SMA water flow: 50.8 g/s.
- SE glycol-water flow: 3.2 g/s.
- Stage times: 3.5/1.5/3.5/1.5 s.

The pressure commands are hydraulic closures from Simscape flow logs. They
are never used to assign a temperature, phase fraction, stress, or heat
quantity.

## Interface and hydraulic fixes

1. `PressurePI_BiasSum` now accepts a continuous `SE_pressure_bias_command`
   with separate Stage 2 and Stage 4 values.
2. The SMA and SE branches use separate axial flow areas. SMA-side TL pipes,
   SMA valves, the SMA pressure source, and the SHEX hot pipe use
   `sma_pipe_fa`; the SE branch remains on `pipe_fa`.
3. The SHEX conductive thermal links retain `area=1`. A previous generic
   area rewrite incorrectly changed this to the liquid flow area and reduced
   actual SHEX heat transfer by several orders of magnitude.
4. Valve commands use a continuous break-before-make profile. The existing
   Simscape valve minimum coefficient is explicitly set to `Cv_min=0.005`
   so closed liquid branches retain a pressure reference.
5. The old common PI lower bound `-0.02 MPa` was replaced by a validated
   `-0.05 MPa` operating bound. A trial at approximately `-0.1 MPa` was
   stopped because the pressure source itself entered an invalid absolute
   pressure region.

## Calibration observations

Intermediate one-cycle outputs were cleaned after the values were transcribed
here. They are not part of the retained result set.

- With the old `-0.02 MPa` saturation, SMA flows were about 22.9/22.5 g/s.
- With independent SMA area and legal pressure, SMA flows reached about
  46.5/45.4 g/s before the final valve-leakage stabilization.
- SE Stage 4 converged near 3.0 g/s. Stage 2 is more hydraulically
  restrictive and was calibrated separately.

## Formal three-cycle result

Retained output:
`gx101r1_R69_remote/outputs/heatdrive_ecc_qian2019_3cycle/qian2019_table2_table4_simscape_3cycle_20260730_123759`

Cycle flow results in kg/s:

| Cycle | SMA Stage 1 | SMA Stage 3 | SE Stage 2 | SE Stage 4 |
|---|---:|---:|---:|---:|
| 1 | 0.05504 | 0.04658 | 0.003386 | 0.002912 |
| 2 | 0.05445 | 0.04662 | 0.006908 | 0.002933 |
| 3 | 0.05443 | 0.04662 | 0.006955 | 0.002930 |

The SMA phase swing is 0.960-1.000 and the SE phase swing is
0.99995-0.999999. CHEX decreases by approximately 0.18-0.24 K per cycle.
All retained temperature probes are finite and span 295.391-393.150 K.

## Strict audit result

The formal validation report is in the retained output directory.

Passed:

- One real Simulink call and physical Simscape authority.
- No legacy surrogate in the result path.
- Three-cycle sample count and 21-node dimensions.
- Solid and probe temperature bounds.
- Phase-fraction bounds and SMA/SE phase swing.
- Active-route and inactive-route isolation checks.
- Qian material, geometry, and stage-schedule contracts.

Not passed:

- `nominal_SMA_stress=0`: maximum SMA stress is about 287.7 MPa versus
  the current 200 MPa Qian nominal-stress check.
- `strict_table4_reproduction_evaluated=0`: periodic steady state,
  no-load/zero-lift cases, and performance metrics have not been run.
- `dual_fluid_domain_implemented=0`: the current SLX still has one shared
  Thermal Liquid settings block, while Qian uses water on the SMA side and
  glycol-water on the SE side.

Therefore this is a reproducible coupled-mechanism checkpoint, not a claim
of completed Qian Table 4 reproduction. The next work should address the
constitutive stress calibration and two-fluid Simscape domain while keeping
one canonical SLX and avoiding new parallel models.

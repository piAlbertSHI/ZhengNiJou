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

## Rejected PI trial

A trial with `se_pressure_pi_kp=0.50 MPa/(kg/s)` was stopped at the first
stage transition because the existing shared pressure-error channel changed
the SMA/SHEX liquid network during an inactive SE stage and produced
Simscape property warnings. The default was restored to zero. No result from
that trial is retained.

## Output retention audit

Before the follow-up Git checkpoint, the obsolete Xu 2019 two-cycle raw
output dated 2026-07-22 was removed. Its conclusions remain in
`2026-07-30_Xu2019当前检查点与Qian重锚定前审计.md`; retaining the 15.2 MB
MAT file and duplicate plots would not add reproducibility because that
parameterization has been superseded by the Qian checkpoint.

Only the formal Qian three-cycle directory
`qian2019_table2_table4_simscape_3cycle_20260730_123759` is retained as
current raw evidence. A rejected one-cycle PI trial did not produce a result
directory. The trial also changed the model default stop time to 10 s and
renumbered Simscape instrumentation SIDs during save; the canonical SLX was
restored byte-for-byte from the verified three-cycle Git checkpoint.

## Table 2/Fig. 5 stress scope correction

The previous `nominal_SMA_stress` gate incorrectly compared the Table 4
prototype geometry against the 200 MPa stress shown by the Table 2/Fig. 5
case. Qian Table 2 uses eight 1.5 mm wires with a 450 mm actuator length and
a 4 mm2, 200 mm SE bed. Substituting that geometry into Qian Eqs. (5)-(8) at
full transformation gives approximately 195 MPa, consistent with the plotted
200 MPa reference.

Table 4 changes the actuator to 32 one-millimetre wires and the SE bed to two
0.5 x 17 mm plates, while specifying a driver/refrigerant mass ratio of 3.2.
The derived geometry in the production model is therefore
`S_r/S_a=0.676408508141` and `L_r/L_a=0.461998919646`. With both
transformation strains equal to 0.03 and both elastic moduli equal to 30 GPa,
the full-transformation compatibility solution is:

`sigma_SMA = 287.697990 MPa`, `sigma_SE = 425.331726 MPa`.

These values are exactly the maxima in the retained physical Simscape logs.
The validator now checks the simulated stress against this analytical
Table 4 Eq. (7)-(8) solution and separately records the scope of the 200 MPa
Fig. 5 reference. It does not clamp or assign stress. Re-auditing the retained
MAT gives `qian_table4_compatibility_stress=1` and
`coupled_mechanism_pass=1`.

This correction does not complete Table 4 reproduction. The dual water /
glycol-water hydraulic domain and the separate post-convergence no-load and
zero-lift performance cases remain mandatory.

## Dual-fluid topology and stage-reset PI completion

The earlier single-domain result and rejected ungated PI trial above are now
superseded. The canonical model remains
`gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx`; no parallel SLX was
created.

The HHEX already contained separate `HotPipe` and `SMAHotPipe` thermal-liquid
channels. The top-level hydraulic junction was corrected by adding a dedicated
`SMAHotFluidBuffer` and a second Thermal Liquid Settings block:

- SMA/SHEX/HHEX-SMA channel: Qian Table 2 water, represented by an embedded
  IAPWS-IF97 liquid-water table at 0.5 MPa over 273.16-413.16 K.
- SE/HHEX-SE/CHEX channel: the declared Qian glycol-water engineering closure
  (`rho=1034.516667 kg/m3`, `cp=3812.666667 J/(kg K)`,
  `mu=0.00228731339 Pa s`, `k=0.452933 W/(m K)`).
- The two hydraulic graphs are disconnected. They exchange heat only through
  the HHEX thermal mass. A model-graph audit verifies two settings blocks,
  both domain connections, hydraulic isolation, and the SMA hot-buffer probe.

The original command profile closed all valves while pump pressure was still
changing. A real one-cycle run then produced a 250.70 K port-temperature
excursion at the Stage 1-to-2 transition. The command sequence is now:

1. keep the outgoing route open and ramp its pressure to zero;
2. switch valves with both pumps unpressurized;
3. ramp the incoming route pressure only after its valves are open.

This removed the Simscape property warnings without temperature clipping or
post-processing deletion.

The retained SE pump PI structure is active again with a real stage-dependent
target of `0.0032 kg/s`. Its settings are `Kp=-1.0 MPa/(kg/s)` and
`Ki=-2.0 MPa/(kg/s s)`, with Stage 2/4 bias pressures
`-0.002754/-0.001480 MPa`. The P path is enabled only during Stages 2/4.
The integrator is held at zero during Stages 1/3 and reset at each active-stage
entry, so Stage 2 and Stage 4 cannot carry integral state into one another.
The controller acts on the physical V1/V4 flow sensors; no flow or temperature
is assigned into the result.

## Retained dual-fluid three-cycle result

Retained output:
`gx101r1_R69_remote/outputs/heatdrive_ecc_dual_fluid_pi_3cycle/qian2019_table2_table4_simscape_3cycle_20260730_220129`

The run used one continuous real `sim()` call and required 721.729 s wall
time. Mean active-route flow rates are:

| Cycle | SMA Stage 1 | SMA Stage 3 | SE Stage 2 | SE Stage 4 |
|---|---:|---:|---:|---:|
| 1 | 0.056360 | 0.049527 | 0.002959 | 0.002898 |
| 2 | 0.056224 | 0.049524 | 0.003250 | 0.002890 |
| 3 | 0.056221 | 0.049524 | 0.003252 | 0.002890 |

All four routes satisfy the added Qian target-flow gate of +/-15 percent.
The previous Stage 2 drift to about 0.00695 kg/s is absent. Inactive SE flow
falls from `4.15e-5` to `1.18e-5 kg/s`; inactive SMA flow remains below 20
percent of active flow.

All mechanism gates pass: real Simscape authority, finite 21-node states and
probes, 50 records per stage, temperature range, phase bounds and phase swing,
analytical Table 4 compatibility stress, state/temperature continuity,
dual-fluid isolation, pump work, and active/inactive flow checks. Over the
three cycles CHEX changes by `-0.2070`, `-0.2384`, and `-0.2420 K`; the SMA
cycle-end mean approaches 315.07 K and the SE cycle-end mean approaches
301.41 K.

`strict_table4_reproduction_evaluated` remains false. Periodic convergence,
the no-load maximum lift case, and the zero-lift specific-cooling case are
separate later acceptance runs and are not claimed from this three-cycle
mechanism result.

After recording these comparisons, the superseded single-domain three-cycle
directory, the failed open-loop dual-fluid three-cycle directory, and all
single-cycle calibration directories were removed. The outputs tree now
retains only the accepted dual-fluid PI three-cycle evidence (33.93 MB).

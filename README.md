# Positive and Reverse Coupled Elastocaloric Cooling

Research code for a heat-driven elastocaloric cooling cycle in which a shape-memory alloy (SMA) drives a separate superelastic (SE) bed. The project studies how phase transformation, fluid routing, heat exchange, and finite fluid inventories interact over four operating stages.

This repository contains a **standalone Python thermal reference** and a **conservative Simscape connector component**. It does not include the full device model, native continuation states, or raw simulation archives.

## Quick Start

Requires Python 3.10 or later with NumPy and SciPy. From the repository root:

```sh
python -m pip install -e .
python -m coupled_cooling.demo --cycles 1
python -m unittest discover -s tests -v
```

The demo runs a synthetic 10 s cycle through all four stages. It reports mean phase fractions, fixed-cold-reservoir reaction heat, and energy, mass, and internal mechanical-work residuals. Inputs are illustrative rather than fitted to a published device. Run with `--step-s 0.01` to compare a finer time step.

## Model Layout

| Path | Contents |
| --- | --- |
| [src/coupled_cooling](src/coupled_cooling) | Conservative face transport, SMA/SE mechanical compatibility, finite inventories, and a fixed-temperature cold boundary with signed reaction heat |
| [simscape](simscape) | Full-EOS thermal-liquid connector with finite friction and explicit mass and internal-energy states |
| [tests](tests) | Checks of flow reversal, property range, thermodynamic identities, and four-stage balance |
| [docs](docs) | Physical assumptions, run evidence, and the claims those results support |

For MATLAB and Simscape, see the [connector build instructions](simscape/README.md). MATLAB is not required to run the Python demo.

## Evidence and Limitations

The Python model uses prescribed flows and a constant-density caloric approximation. It is not equivalent to the closed-loop compressible Simscape device. The connector component is a separate hydraulic and thermal-liquid building block.

A same-volume native cold-cycle comparison found a 24% to 25% reduction in connector mass swing when part of the common volume was moved into the two branches. First-cycle cooling remained essentially unchanged. Finite-resistance fixtures show that the split reduces pressure loss relative to a fully resistive common layout, but still requires additional head relative to the pressure-transparent reference. See [research evidence and limits](docs/model-scope.md) for the test conditions.

The current configuration has **not reproduced the paired Table 4 benchmarks**. The demo is not a periodic steady-state, hardware-validation, or cooling-power benchmark.

## References and License

- [Qian et al., *A heat driven elastocaloric cooling system*, Energy (2019)](https://doi.org/10.1016/j.energy.2019.06.094), cycle architecture and benchmark conditions.
- [Mandolino et al., IEEE Robotics and Automation Letters (2021)](https://doi.org/10.1109/LRA.2021.3067254), equations used in the independent material energy model.

The repository is publicly viewable. No license has been specified for the source code. Third-party papers and proprietary software are not included.

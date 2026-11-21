# Conservative Thermal-Liquid Connector

`+ecc_inventory/conservative_chamber.ssc` defines a rigid connector with two thermal-liquid ports and one thermal port.

- The state equations accumulate mass and internal energy from signed port fluxes.
- Pressure and temperature close against the thermal-liquid network property tables.
- Each fluid port has a half-length pressure loss. The component calls the installed Simscape friction and convection functions; it does not bundle MathWorks source code or property tables.
- Volume must equal cross-sectional area times physical length. Friction and convective characteristic length are declared separately.

## Build

Use MATLAB and Simscape R2025b. In a MATLAB session, set the current folder to this `simscape` directory and run:

```matlab
ssc_build('ecc_inventory')
open_system('ecc_inventory_lib')
```

Connect the block to a thermal-liquid network that defines a property domain, pressure reference, and Solver Configuration. Set the geometry and initial thermodynamic coordinates explicitly; the default roughness is an assumption, not an experimental measurement.

Generated libraries, solver caches, and run outputs are intentionally not tracked. See [model scope](../docs/model-scope.md) for the limits of the connector experiments.

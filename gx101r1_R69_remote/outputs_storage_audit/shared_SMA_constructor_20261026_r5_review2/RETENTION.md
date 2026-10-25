# Shared SMA Constructor Evidence

## Authority

- Actual constructor producer: 5df7636; MATLAB natural exit 0, session 66391.
- Independent source-bound review: 1874f5f; shared_SMA_wire_review.json is
  authoritative over the earlier preliminary r5 reader output.
- Keep before/after liquid and thermal JSON, execution/intervention JSON,
  final review, all four failure receipts, five final logs and cleanup receipt.
- Copied original files were verified by SHA-256. No result MAT/OP/full-step
  trajectory was generated or copied.
- Raw MATLAB console logs retain original control characters and trailing
  spaces; the exact log paths have a scoped whitespace-check exception, not
  a content rewrite or a scientific gate change.

## What Passed

The exact liquid wire partition differs only by retiring 21 cooling pipes and
the declared three joins. All surviving thermal wire partitions are unchanged.
The original hot/cold commands actually feed a max block and the retained gate.
The remaining 21 fluid pipes retain their geometry and initial expressions.

## What Did Not Run

No compile, cold initialization, accepted time step, pressure/flow gate,
switch continuity test, energy balance, periodic cycle or Table4 audit ran.
This is not a restart checkpoint or a twenty-cycle seed.

The inherited retained fluid starts at Tshex=393.15 K; the deleted cooling
representation started at Thhex=303.15 K. Neither this constructor nor its
reduced fluid capacity proves a uniform cold protocol or improved performance.
Next physics comparison must explicitly match initial conditions, preserving
all boundary temperatures, materials and geometry. Do not load an old OP.

## Regeneration / Cleanup

Five temporary Git model copies were byte-identical to the tracked source,
not distinct physical results. Only those exact files were removed after
path, hash, size and active-process checks. Logical bytes retired: 2,185,140.
The seed archive and tracked Git model remain available for reconstruction.
No earlier policy-denied path was retried or bypassed.

Temporary C:/tmp constructor directories still contain small graph evidence
and empty/generated directories. They are not production restore roots.
Source configuration and the retained specific-inventory component library
remain live dependencies for repeating this diagnostic; do not remove them.

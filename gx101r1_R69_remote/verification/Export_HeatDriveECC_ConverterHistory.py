"""Extract four C200 input samples for an isolated converter history replay."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite evidence')
    contract = json.loads((args.repo/'verification/c200_mainline_freeze_contract.json').read_text(encoding='utf-8-sig'))
    source = args.repo/contract['result_relative_path']
    digest = sha256(source)
    if digest != contract['result_sha256']:
        raise ValueError('Frozen C200 changed')
    with h5py.File(source) as f:
        p = f['physical']
        t = p['time_s'][0,-4:]
        if not np.array_equal(t,[1999.997,1999.998,1999.999,2000]):
            raise ValueError('Missing exact pre-boundary sample grid')
        rows = []
        for side in ('SMA','SE'):
            q = p[f'Q_{side}_constitutive_21_W'][:,-4:]
            if q.shape != (21,4) or not np.all(np.isfinite(q)) or np.any(q[:,-1]!=0):
                raise ValueError('Unexpected input history')
            for k in range(21):
                rows.append(dict(block_path=f'heatdrive_ecc_coupled_se21/{side}/Subsystem2/ConstitutiveHeatPS_{k+1:02d}',
                                 values_W=q[k].tolist()))
    result = dict(schema='heatdrive_ecc_converter_history_input_v1',source_sha256=digest,
                  time_s=t.tolist(),rows=rows,production_recovery_allowed=False)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(dict(channels=len(rows),samples=len(t),source_sha256=digest)))


if __name__=='__main__':
    main()

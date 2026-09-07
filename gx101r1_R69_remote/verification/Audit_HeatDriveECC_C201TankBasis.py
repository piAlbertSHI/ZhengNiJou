"""Test the prior independent tank hypothesis on the unmodified C201 trajectory."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

from Audit_HeatDriveECC_C201Inventory import load_native
from Audit_HeatDriveECC_C201InventoryPackage import scope
from Audit_HeatDriveECC_C200StateCapture import archived_source
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_TankEnergyBasis import analyze,DEAD_HEIGHT_M,TRIAL_COMMIT
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def geometry(row):
    modes=row['model_modes']
    if not modes['num_inlet'].endswith('.One') or not modes['volume_spec'].endswith('.Constant'):
        raise ValueError('Only the observed constant-area one-inlet tanks are supported')
    parameters=row['mask_parameters']
    values=[]
    for name,unit in (('tank_area','m^2'),('g','m/s^2'),('inlet_height_A','m')):
        field=parameters[name]
        value=float(field['value'])
        if field['unit']!=unit or not np.isfinite(value) or value<0 or (name=='tank_area' and value==0):
            raise ValueError('Invalid actual tank geometry')
        values.append(value)
    return values


def metadata_matches(old,new):
    for key,value in old.items():
        if key!='storage_blocks' and new[key]!=value:
            raise ValueError('Archival model metadata changed: '+key)
    before={r['block_path']:r for r in old['storage_blocks']}
    after={r['block_path']:r for r in new['storage_blocks']}
    if set(before)!=set(after):
        raise ValueError('Inventory identity changed')
    for path,row in before.items():
        for key,value in row.items():
            current=after[path][key]
            if isinstance(value,dict):
                if any(current[k]!=v for k,v in value.items()):
                    raise ValueError('Old component parameter changed')
            elif current!=value:
                raise ValueError('Old component identity changed')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output-root',type=Path,required=True)
    args=parser.parse_args()
    repo=args.repo.resolve()
    root=repo/'outputs_storage_audit'
    target=args.output_root.resolve()
    if target.exists():
        raise FileExistsError('Preserve prior diagnostic evidence')
    target.mkdir(parents=True)
    old_path=root/'c201_inventory_20260907_v2/inventory_metadata.json'
    new_path=root/'c201_tank_geometry_20260907/inventory_metadata.json'
    frozen_path=root/'c201_inventory_20260907_v2/native_inventory_v2.json'
    old,new,frozen=read(old_path),read(new_path),read(frozen_path)
    scope(frozen)
    metadata_matches(old,new)
    source=archived_source(root/'c200_source_compatibility_20260907')
    for relative,digest in frozen['input_sha256'].items():
        path=(repo/relative).resolve()
        if not path.is_relative_to(repo) or sha256(path)!=digest:
            raise ValueError('C201 input changed: '+relative)
    trial_path=target/'independent_trial_reaudit.json'
    with (target/'independent_trial_reaudit.log').open('w',encoding='utf-8') as log:
        subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_TankEnergyBasis.py'),
                        '--repo',str(repo),'--output',str(trial_path)],stdout=log,stderr=subprocess.STDOUT,check=True)
    trial=read(trial_path)
    if (not trial['independent_dead_volume_hypothesis_pass'] or trial['trial_execution_commit']!=TRIAL_COMMIT
            or trial['dead_height_m']!=DEAD_HEIGHT_M or trial['fitted_correction_used']
            or trial['production_recovery_allowed']):
        raise ValueError('Prior independent hypothesis not verified')
    assignment,_=resolve_domains(read(root/'c201_inventory_20260907_v2/tl_connectivity.json'))
    tables={r['block_path']:energy_tables(r['parameters']) for r in new['settings_tables']}
    native=load_native(root/'c201_bounded_20260907')
    previous={r['block_path']:r for r in frozen['components']}
    rows=[]
    for original in new['storage_blocks']:
        if original['mask_type']!='Tank (TL)':
            continue
        block=copy.deepcopy(original)
        path=block['block_path']
        block['leaf_variables']=[dict(name=k[1],**v) for k,v in native.items() if k[0]==path]
        row=analyze(block,tables[assignment[path]],*geometry(block))
        if not np.isclose(row['original_BE_energy_residual_J'],previous[path]['BE_coefficient_energy_residual_J_end'],atol=1e-11,rtol=1e-11):
            raise ValueError('Original C201 residual could not be reproduced')
        row['original_endpoint_energy_residual_J']=previous[path]['endpoint_energy_residual_J_end']
        rows.append(row)
    if len(rows)!=4:
        raise ValueError('Missing tank evidence')
    paths=[old_path,new_path,frozen_path,trial_path,root/'c201_tank_geometry_stdout_20260907.log']
    result=dict(schema='heatdrive_ecc_c201_tank_basis_v1',source=source,
                metadata_export_source_commit='23212fd',hypothesis_trial_source_commit=TRIAL_COMMIT,
                independent_trial_reaudit_pass=True,hypothesis_fitted_to_C201=False,dead_height_m=DEAD_HEIGHT_M,
                tank_count=4,samples_per_tank=10001,intervals_omitted=0,tanks=rows,
                original_coefficient_energy_residual_J=sum(r['original_BE_energy_residual_J'] for r in rows),
                extra_thermal_accumulation_J=sum(r['extra_BE_accumulation_J'] for r in rows),
                hydrostatic_transport_J=sum(r['hydrostatic_internal_transport_BE_J'] for r in rows),
                identified_equation_residual_J=sum(r['extra_volume_and_head_BE_residual_J'] for r in rows),
                all_tank_intervals_match_prior_equation=all(r['extra_volume_and_head_BE_roundoff_match'] for r in rows),
                old_endpoint_residual_not_erased=True,full_device_first_law_verified=False,
                production_recovery_allowed=False,table4_reproduction_claim=False,
                input_sha256={str(p):sha256(p) for p in paths})
    (target/'c201_tank_basis.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('tanks','input_sha256','source')},indent=2))
    if not result['all_tank_intervals_match_prior_equation']:
        raise SystemExit(1)


if __name__=='__main__':
    main()

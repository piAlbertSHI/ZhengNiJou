"""Freeze bounded existing-data checks; never run MATLAB or delete raw evidence."""
import json
from pathlib import Path
import shutil
import subprocess
import sys

from Analyze_HeatDriveECC_NativeConsistencyProbe import require_equal
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


def main():
    repo=Path(__file__).resolve().parents[1];audit=repo/'outputs_storage_audit'
    previous=audit/'coupled_CV_C2_balance_20261026_r4'
    output=audit/'coupled_CV_C2_balance_20261026_r6'
    prefix=Path('C:/tmp/se21_shared_consistency_tight_prefix_r1_20261026')
    receipt=output/'closeout_verification.json'
    if receipt.exists():raise ValueError('Never overwrite a completed closeout')
    read=lambda p:json.loads(p.read_text(encoding='utf-8'))
    prior=read(previous/'closeout_verification.json')
    verified=[]
    for row in prior['mainline']+prior['current_verified_input_dependencies']:
        p=Path(row['path'])
        if sha256(p)!=row['sha256']:raise ValueError('Frozen input changed: '+str(p))
        verified.append(dict(path=str(p),sha256=row['sha256'],bytes=p.stat().st_size))
    protected=repo/'heatdrive_ecc_coupled_se21.slx'
    if sha256(protected)!=prior['protected_model_sha256']:raise ValueError('Protected model changed')
    old,new=read(previous/'coupled_CV_balance.json'),read(output/'coupled_CV_balance.json')
    for a,b in zip(old['arms'],new['arms'],strict=True):
        require_equal(a['arm'],b['arm'],'arm')
        require_equal(a['Eq9_Eq10_diagnostics'],b['Eq9_Eq10_diagnostics'],'Eq9_Eq10')
        for x,y in zip(a['windows'],b['windows'],strict=True):
            for key in x:
                if key!='components':require_equal(x[key],y[key],key)
            for c,d in zip(x['components'],y['components'],strict=True):
                for key in c:
                    if key!='basis':require_equal(c[key],d[key],key)
    modules=['test_coupled_CV_balance','test_coupled_CV_packet','test_native_consistency_probe',
             'test_tank_energy_basis','test_c201_tank_basis','test_tank_interpolation_consistency',
             'test_native_accumulation','test_native_window_ledger','test_native_inventory_catalog',
             'test_native_window_packets','test_native_residual_localization','test_native_state_mapping',
             'test_native_series_access_source','test_native_log_lookup_source',
             'test_shared_SMA_cold_initial','test_shared_SMA_fluid','test_shared_SMA_native_ledger',
             'test_coupled_energy_inventory','test_material_thermodynamics']
    run=subprocess.run([sys.executable,'-X','utf8','-m','unittest',*modules],cwd=repo/'verification',
                       stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    (output/'targeted_tests.log').write_bytes(run.stdout)
    if run.returncode:raise ValueError('Targeted tests failed; see retained log')
    raw=[dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted((prefix/'shared').glob('*.mat'))]
    if len(raw)!=4:raise ValueError('Unexpected prefix raw coverage')
    execution=output/'tight_prefix_execution';execution.mkdir(exist_ok=False)
    for path in (prefix/'coupled_CV_execution.json',prefix/'shared/completed_initial_probe.json',
                 prefix/'shared/cold_preflight.json',prefix/'shared/numerical_solver_contract.json',
                 prefix/'shared/solver_time.json',Path(str(prefix)+'.log')):
        shutil.copyfile(path,execution/path.name)
    # Scope is these new result folders and this raw prefix, never the workspace.
    groups=[]
    for path,role in ((prefix,'single-copy numerical diagnostic raw and regenerable constructor/cache'),
                      (output,'authoritative corrected C2 analysis and regression evidence'),
                      (audit/'coupled_CV_C2_balance_20261026_r5','regenerable intermediate analysis'),
                      (audit/'native_consistency_prefix_20261026_r2','prior comparator evidence'),
                      (audit/'native_consistency_prefix_20261026_r3','corrected numerical comparator evidence')):
        files=[]
        for p in path.rglob('*'):
            if p.is_symlink():raise ValueError('Unexpected link in bounded storage scope')
            if p.is_file():files.append(p)
        groups.append(dict(path=str(path),file_count=len(files),bytes=sum(p.stat().st_size for p in files),role=role))
    result=dict(schema='heatdrive_ecc_native_tank_closure_closeout_v1',
        execution_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
        prior_receipt_sha256=sha256(previous/'closeout_verification.json'),
        reverified_frozen_dependencies=verified,protected_model_sha256=sha256(protected),
        corrected_analysis_sha256=sha256(output/'coupled_CV_balance.json'),
        control_volume_table_sha256=sha256(output/'control_volume_table.csv'),
        numerical_comparison_sha256=sha256(audit/'native_consistency_prefix_20261026_r3/native_consistency_comparison.json'),
        legacy_scalars_endpoints_and_Eq9_Eq10_preserved_exactly=True,
        targeted_test_modules=modules,targeted_test_return_code=run.returncode,targeted_test_log_sha256=sha256(output/'targeted_tests.log'),
        new_prefix_raw_files=raw,new_prefix_raw_bytes=sum(r['bytes'] for r in raw),
        prefix_matlab_session=78885,prefix_matlab_natural_exit_code=0,
        prefix_wall_simulation_seconds=136.2465352,prefix_process_cpu_seconds=151.09375,
        first_comparator_failure='matching NaN metadata and generated schedule horizons; no physical change; repaired before reuse',
        first_comparator_failure_directory_created=False,storage_snapshot_excludes_this_receipt=groups,
        prefix_raw_copied=False,deleted_files=0,reclaimed_bytes=0,
        new_MATLAB_run_in_this_offline_closeout=False,physical_endpoint_first_law_verified=False,
        production_recovery_allowed=False,strict_Table4_reproduction=False,goal_complete=False)
    write_json(receipt,result)
    print(json.dumps(dict(output=str(output),tests_exit=run.returncode,raw_bytes=result['new_prefix_raw_bytes'],
                         legacy_outputs_preserved=True,goal_complete=False)))


if __name__=='__main__':main()

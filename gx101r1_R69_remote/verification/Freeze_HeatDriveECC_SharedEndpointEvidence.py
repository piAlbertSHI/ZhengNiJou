"""Freeze small endpoint C2 evidence and bounded storage/dependency accounting."""
import json
from pathlib import Path
import shutil
import subprocess
import sys

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


def main():
    repo=Path(__file__).resolve().parents[1];audit=repo/'outputs_storage_audit'
    out=audit/'shared_endpoint_inventory_C2_20261026_r2'
    read=lambda p:json.loads(p.read_text(encoding='utf-8'))
    receipt=out/'closeout_verification.json'
    if receipt.exists():raise ValueError('Do not overwrite a completed freeze')
    raw=Path('C:/tmp/se21_shared_endpoint_inventory_C2_r1_20261026')
    smoke=Path('C:/tmp/se21_shared_endpoint_inventory_smoke_r2_20261026')
    rejected=Path('C:/tmp/se21_shared_endpoint_inventory_smoke_r1_20261026')
    baseline=audit/'coupled_CV_C2_balance_20261026_r6/coupled_CV_balance.json'
    new_path=audit/'shared_endpoint_inventory_C2_balance_20261026_r1/coupled_CV_balance.json'
    native=next(r for r in read(baseline)['arms'] if r['arm']=='shared')
    endpoint=read(new_path)['arms'][0];probe=read(out/'endpoint_inventory_probe.json')
    if not probe['initialization_contract_runtime_hash_bound']:raise ValueError('Missing bound cold recipe')
    a=native['Eq9_Eq10_diagnostics'][1];b=endpoint['Eq9_Eq10_diagnostics'][1]
    metric_keys=['Eq10_measured_pipe_flow_declared_cp_W','all_cycle_CHEX_sensor_W','Eq9_fixed_downstream_port_lift_K']
    comparison={k:dict(native=a[k],endpoint=b[k],endpoint_minus_native=b[k]-a[k],relative_change=(b[k]-a[k])/a[k]) for k in metric_keys}
    # The new buffer's endpoint includes declared pV/gravity/auxiliary energy;
    # retaining this scope avoids misrepresenting closure as performance gain.
    comparison['energy_boundary_not_identical_between_native_and_endpoint']=True
    comparison['cold_C2_metrics_are_not_periodic_performance']=True
    comparison['native_analysis_sha256']=sha256(baseline);comparison['endpoint_analysis_sha256']=sha256(new_path)
    write_json(out/'same_window_native_endpoint_comparison.json',comparison)
    prior=read(audit/'coupled_CV_C2_balance_20261026_r6/closeout_verification.json')
    inputs=[]
    for row in prior['reverified_frozen_dependencies']:
        path=Path(row['path'])
        if sha256(path)!=row['sha256']:raise ValueError('Frozen baseline input changed: '+str(path))
        inputs.append(row)
    protected=repo/'heatdrive_ecc_coupled_se21.slx'
    if sha256(protected)!=prior['protected_model_sha256']:raise ValueError('Protected model changed')
    modules=['test_shared_endpoint_inventory','test_coupled_CV_packet','test_coupled_CV_balance',
             'test_native_consistency_probe','test_tank_energy_basis','test_c201_tank_basis',
             'test_tank_interpolation_consistency','test_native_accumulation','test_native_window_ledger',
             'test_native_inventory_catalog','test_native_window_packets','test_native_residual_localization',
             'test_native_state_mapping','test_native_series_access_source','test_native_log_lookup_source',
             'test_shared_SMA_cold_initial','test_shared_SMA_fluid','test_shared_SMA_native_ledger',
             'test_coupled_energy_inventory','test_material_thermodynamics','test_cold_buffer_coupled']
    run=subprocess.run([sys.executable,'-X','utf8','-m','unittest',*modules],cwd=repo/'verification',
                       stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    (out/'targeted_tests.log').write_bytes(run.stdout)
    if run.returncode:raise ValueError('Tests failed; retained output is not a pass')
    meta=out/'execution_metadata';meta.mkdir(exist_ok=False)
    for root,tag in ((raw,'C2'),(smoke,'smoke')):
        dest=meta/tag;dest.mkdir()
        for path in [root/'coupled_CV_execution.json',*[root/'shared'/name for name in
                     ('completed_initial_probe.json','endpoint_inventory_construction.json','cold_preflight.json',
                      'CV_contract.json','solver_time.json','solver_time.jsonl')],Path(str(root)+'.log')]:
            shutil.copyfile(path,dest/path.name)
    shutil.copyfile(rejected/'FAILED_DO_NOT_RESUME.json',meta/'rejected_constructor_r1.json')
    shutil.copyfile(Path(str(rejected)+'.log'),meta/'rejected_constructor_r1.log')
    new_raw=[];storage=[];candidates=[]
    for root,role in ((raw,'current independent cold C2 raw; not a continuation OP'),
                      (smoke,'first compiled endpoint smoke and independent onset evidence'),
                      (rejected,'pre-simulation constructor failure; never resume')):
        mats=list((root/'shared').glob('*.mat'))
        for path in mats:new_raw.append(dict(path=str(path),bytes=path.stat().st_size,sha256=sha256(path)))
        files=list(p for p in root.rglob('*') if p.is_file())
        storage.append(dict(path=str(root),bytes=sum(p.stat().st_size for p in files),file_count=len(files),role=role))
        for suffix in ('cache','codegen','shared/seed'):
            target=root/suffix
            if not target.is_dir():continue
            if any(p.is_symlink() for p in target.rglob('*')):raise ValueError('Unexpected link in generated tree')
            rows=[dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p)) for p in target.rglob('*') if p.is_file()]
            candidates.append(dict(path=str(target),workspace_root=str(root),files=rows,bytes=sum(r['bytes'] for r in rows),
                                   purpose='regenerable constructor copy or passive Simulink cache; not a raw result/OP/source'))
    write_json(out/'generated_intermediate_candidates.json',dict(schema='heatdrive_ecc_generated_candidates_v1',
        candidates=candidates,expected_raw_before_after=new_raw,files_deleted_by_this_script=0))
    result=dict(schema='heatdrive_ecc_shared_endpoint_C2_closeout_v1',
        execution_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
        corrected_C2_probe_sha256=sha256(out/'endpoint_inventory_probe.json'),
        C2_balance_sha256=sha256(new_path),comparison_sha256=sha256(out/'same_window_native_endpoint_comparison.json'),
        raw_dependencies=new_raw,new_raw_MAT_bytes=sum(r['bytes'] for r in new_raw),
        protected_model_sha256=sha256(protected),frozen_baseline_dependencies_reverified=inputs,
        test_modules=modules,targeted_tests_exit=run.returncode,targeted_tests_log_sha256=sha256(out/'targeted_tests.log'),
        sessions=[dict(session=28320,exit_code=1,scope='constructor only; JSON vector shape assertion before simulation'),
                  dict(session=73824,exit_code=0,scope='compiled 0.01 s onset'),
                  dict(session=66034,exit_code=0,scope='continuous cold 20 s; TWO cycles not twenty')],
        first_reader_failure='kJ/kg target is not SI output unit; repaired without MATLAB rerun',
        bounded_storage_before_retirement=storage,
        generated_retirement_candidate_bytes=sum(r['bytes'] for r in candidates),
        raw_MAT_copied_to_Git=False,OP_or_checkpoint_loaded_or_saved=False,
        full_C20_raw_linear_estimate_bytes=10*sum(r['bytes'] for r in new_raw if str(raw) in r['path']),
        estimate_scope='rough linear disk estimate only; compression/trajectory/peak memory are uncertain; prefer late-cycle logging before C20',
        all_mechanism_gates_evaluated=False,full_device_validation=False,production_recovery_allowed=False,
        periodic_steady_state=False,Table4_reproduced=False,goal_achieved=False)
    write_json(receipt,result)
    print(json.dumps(dict(output=str(out),test_exit=run.returncode,new_raw_bytes=result['new_raw_MAT_bytes'],
                         candidate_bytes=result['generated_retirement_candidate_bytes'],goal_achieved=False)))


if __name__=='__main__':main()

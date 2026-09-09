"""Preserve an incomplete run without inventing an exit code or scientific result."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def audit(repo):
    name='specific_inventory_analytic_derivative_onset_20260909'
    root=repo/'outputs_storage_audit'/name
    command="$ErrorActionPreference='Stop'; ConvertTo-Json -InputObject @(Get-CimInstance Win32_Process -Filter \"Name='MATLAB.exe'\" | Where-Object {$_.CommandLine -like '*"+name+"*'} | Select-Object ProcessId,ParentProcessId,CommandLine) -Compress"
    completed=subprocess.run(['pwsh','-NoProfile','-Command',command],check=True,capture_output=True,text=True,encoding='utf-8')
    processes=json.loads(completed.stdout)
    if processes:raise ValueError('The real MATLAB process still exists; do not classify it as stopped')
    absent=['compiled_states_inspection.json','observations.mat','failed_public_observations.mat','compiled_initial_state_dataset.mat']
    if any((root/f).exists() for f in absent):raise ValueError('New terminal evidence exists; inspect it instead')
    diary=root/'matlab_diary.log';text=diary.read_text(encoding='utf-8-sig')
    loop=['Solver Configuration/EVAL_KEY/STATE_1','Solver Configuration/EVAL_KEY/OUTPUT_1_0',
          'SMAPressurePI_ErrorSum','SMAPressurePI_ErrorNormalizer','ColdPressureDerivative',
          'Solver Configuration/EVAL_KEY/INPUT_47_1_1']
    if not all(s in text for s in loop):raise ValueError('Expected algebraic-loop evidence missing')
    freeze=repo/'verification/c200_mainline_freeze_contract.json';f=read(freeze);files=[diary,freeze]
    for key in ('result','checkpoint'):
        p=repo/f[key+'_relative_path']
        if sha256(p)!=f[key+'_sha256']:raise ValueError('C200 changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_incomplete_onset_evidence_v1',inspected_at_utc=datetime.now(timezone.utc).isoformat(),
        run_directory=str(root),matching_live_processes=processes,missing_terminal_files=absent,
        original_exec_session=80539,last_known_launcher_pid=42720,last_known_worker_pid=10552,
        terminal_exit_code=None,termination_cause='unconfirmed',actual_final_simulation_time_s=None,
        requested_stop_time_s=.2,algebraic_loop_reported=True,reported_loop_blocks=loop,
        loop_discontinuity_reported='discontinuity' in text,run_completed=False,
        initial_coordinate_gate=None,trajectory_conservation_gate=None,production_recovery_allowed=False,
        restart_performed=False,scientific_failure_proven=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in files})


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True);args=p.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite interruption evidence')
    result=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'incomplete_run_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},indent=2))

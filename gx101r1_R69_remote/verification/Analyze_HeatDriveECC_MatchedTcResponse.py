"""Compare qualified Tc trials at a common initial OP, recipe and measured window."""
import argparse
import copy
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read


METRICS=('cooling_power_eq10_W','SCP_W_per_g','temperature_lift_eq9_K','CHEX_sensor_mean_W','heat_driven_COP')


def same_experiment(low, high, a, b, left_recipe, right_recipe):
    for q in (low,high):
        if (q['schema']!='heatdrive_ecc_runtime_Tc_candidate_endpoint_v1' or
                not q['all_original_packet_mechanism_flow_phase_energy_gates_pass'] or
                not q['all_four_memories_bitwise_preserved'] or not q['original_public_thermal_periodic_pass'] or
                not q['transition_excluded'] or q['source_state_edited'] or q['old_model_OP_imported']):
            raise ValueError('Both points must independently pass their original packet and current thermal gates')
    lt,rt=copy.deepcopy(low['boundary_trial']),copy.deepcopy(high['boundary_trial'])
    for key in ('candidate_Tc_K','plant_recipe_sha256'):lt.pop(key);rt.pop(key)
    lr,rr=copy.deepcopy(left_recipe),copy.deepcopy(right_recipe)
    for key in ('output_root','diagnostic_observation_options'):lr.pop(key);rr.pop(key)
    if (lt!=rt or lr!=rr or low['current_window_s']!=high['current_window_s'] or
            low['snapshot_time_s']!=high['snapshot_time_s'] or not low['temperature_K']<high['temperature_K'] or
            a['window_s']!=b['window_s'] or a['window_s']!=low['current_window_s'] or
            a['sample_count']!=b['sample_count'] or a['sample_count']!=100001 or
            a['active_SE_mass_kg']!=b['active_SE_mass_kg'] or a['fluid_cp_J_per_kgK']!=b['fluid_cp_J_per_kgK'] or
            [(r['cycle'],r['window_s']) for r in a['cycles']]!=[(r['cycle'],r['window_s']) for r in b['cycles']]):
        raise ValueError('No comparison across unmatched source states, physical recipes, windows or metric bases')


def response(low, high, a, b):
    dt=high['temperature_K']-low['temperature_K'];rows={}
    for key in METRICS:
        delta=np.array([y[key]-x[key] for x,y in zip(a['cycles'],b['cycles'])])
        rows[key]=dict(low=a['performance'][key],high=b['performance'][key],
            difference=b['performance'][key]-a['performance'][key],
            finite_step_response_per_K=(b['performance'][key]-a['performance'][key])/dt,
            cycle_difference_min=float(delta.min()),cycle_difference_max=float(delta.max()),
            cycle_difference_span=float(np.ptp(delta)),cycle_differences=delta.tolist(),
            deterministic_cycle_spread_is_not_a_confidence_interval=True)
    bracket=lambda key:a['performance'][key]*b['performance'][key]<=0
    return dict(metrics=rows,zero_load_SCP_bracketed=bracket('SCP_W_per_g'),
        zero_lift_bracketed=bracket('temperature_lift_eq9_K'),root_found=False,
        zero_load_local_direction=('decrease_Tc' if rows['SCP_W_per_g']['difference']>0 else
            'increase_Tc' if rows['SCP_W_per_g']['difference']<0 else 'unresolved'),
        zero_lift_local_direction=('increase_Tc' if rows['temperature_lift_eq9_K']['difference']<0 else
            'decrease_Tc' if rows['temperature_lift_eq9_K']['difference']>0 else 'unresolved'),
        parameter_extrapolation_performed=False,asymptotic_derivative_claim=False,outer_solve_eligible=False,
        paired_Table4_eligible=False,table4_reproduction_claim=False)


def load_qualified(path):
    q=read(path)
    for f in q['files']:
        if sha256(Path(f['path']))!=f['sha256']:raise ValueError('Changed qualified dependency: '+f['path'])
    if sha256(Path(q['operating_point_path']))!=q['operating_point_sha256']:raise ValueError('Changed trial OP')
    files=[Path(f['path']) for f in q['files']]
    windows=[p for p in files if p.name=='measured_window.json' and
             read(p).get('schema')=='heatdrive_ecc_measured_ten_cycle_collection_v1']
    recipes=[p for p in files if p.name=='initial_prepared_recipe.json']
    comparisons=[p for p in files if p.name=='runtime_Tc_recipe_comparison.json']
    if any(len(rows)!=1 for rows in (windows,recipes,comparisons)):raise ValueError('Ambiguous trial evidence')
    check=read(windows[0].parent/'endpoint_load_check.json')
    if (not check['actual_complete_OP_loaded'] or check['simulation_executed'] or check['source_state_edited'] or
            check['snapshot_time_s']!=q['snapshot_time_s'] or check['operating_point_sha256']!=q['operating_point_sha256']):
        raise ValueError('Require the independent actual full-OP reload')
    return q,read(windows[0]),read(recipes[0]),read(comparisons[0]),windows[0].parent/'endpoint_load_check.json'


def configuration_origin(q,seen=None):
    """Follow SHA-bound same-Tc ancestry, not equality of differently labelled MAT files."""
    seen=set() if seen is None else seen
    comparisons=[f for f in q['files'] if Path(f['path']).name=='runtime_Tc_recipe_comparison.json']
    if len(comparisons)!=1:raise ValueError('Ambiguous actual construction comparison')
    if sha256(Path(comparisons[0]['path']))!=comparisons[0]['sha256']:raise ValueError('Changed construction comparison')
    c=read(comparisons[0]['path'])
    if not c['only_declared_change'] or not c['numeric_validation_thresholds_equal']:
        raise ValueError('An ancestor changed physical options or validation thresholds')
    if not q.get('same_Tc_continuation',False):return c['reference_configuration_sha256']
    if c.get('reference_options_field')!='plant_build_options':raise ValueError('Continuation must compare the original plant recipe')
    results=[f for f in q['files'] if Path(f['path']).name=='collection_result.json']
    if len(results)!=1:raise ValueError('Ambiguous continuation lineage')
    if sha256(Path(results[0]['path']))!=results[0]['sha256']:raise ValueError('Changed continuation record')
    continuation=read(results[0]['path'])['continuation'];digest=continuation['source_qualification_sha256']
    if digest in seen:raise ValueError('Cyclic source qualification')
    seen.add(digest);sources=[Path(f['path']) for f in q['files'] if f['sha256']==digest]
    if not sources or sha256(sources[0])!=digest:raise ValueError('Changed ancestor qualification')
    parent=read(sources[0])
    if (parent['temperature_K']!=q['temperature_K'] or parent['boundary_trial']!=q['boundary_trial'] or
            parent['operating_point_sha256']!=continuation['source_OP_sha256'] or
            parent['snapshot_time_s']!=continuation['source_snapshot_s'] or
            parent['snapshot_time_s']>=q['snapshot_time_s'] or
            sha256(Path(parent['operating_point_path']))!=parent['operating_point_sha256']):raise ValueError('Unmatched same-Tc ancestry')
    return configuration_origin(parent,seen)


def analyze(low,high,output,figure):
    if output.exists() or any(figure.with_suffix(s).exists() for s in ('.png','.pdf','.json')):
        raise FileExistsError('Use fresh comparison and figure paths')
    l,a,lr,lc,lcheck=load_qualified(low);h,b,hr,hc,hcheck=load_qualified(high)
    same_experiment(l,h,a,b,lr,hr)
    if (not all(c['only_declared_change'] and c['numeric_validation_thresholds_equal'] for c in (lc,hc)) or
            configuration_origin(l)!=configuration_origin(h) or
            lc['other_option_groups_equal']!=hc['other_option_groups_equal'] or
            lc['numeric_validation_fields_equal']!=hc['numeric_validation_fields_equal']):
        raise ValueError('The measured plant-build comparisons do not share the same baseline contract')
    result=response(l,h,a,b)
    result.update(schema='heatdrive_ecc_matched_source_finite_window_Tc_response_v1',
        analysis_source_sha256=sha256(Path(__file__)),
        source_OP_sha256=l['boundary_trial']['source_complete_OP_sha256'],
        source_qualification_sha256=l['boundary_trial']['source_qualification_sha256'],
        temperatures_K=[l['temperature_K'],h['temperature_K']],common_window_s=a['window_s'],
        common_physical_recipe_verified=True,numeric_validation_thresholds_unchanged=True,
        common_ancestral_configuration_sha256=configuration_origin(l),
        intervention_transition_excluded=True,active_SE_mass_kg=a['active_SE_mass_kg'],
        fluid_cp_J_per_kgK=a['fluid_cp_J_per_kgK'],response_type='Controlled finite-time, finite-step difference',
        source_state_edited=False,production_recovery_allowed=False,
        input_sha256=[dict(path=str(p.resolve()),sha256=sha256(p)) for p in (low,high,lcheck,hcheck)])
    output.mkdir(parents=True);(output/'matched_Tc_response.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    plt.rcParams.update({'font.family':'Arial','font.size':10,'pdf.fonttype':42})
    fig,axes=plt.subplots(2,2,figsize=(12,7.6),layout='constrained');x=[r['cycle'] for r in a['cycles']]
    for row,key,unit,title in ((0,'cooling_power_eq10_W','W','Eq.10 cooling'),
                               (1,'temperature_lift_eq9_K','K','Eq.9 lift')):
        for data,q,color in ((a,l,'#00796B'),(b,h,'#B54464')):
            axes[row,0].plot(x,[r[key] for r in data['cycles']],'-o',ms=3,color=color,label=f'Tc={q["temperature_K"]:.2f} K')
        axes[row,0].set(xlabel='Global cycle',ylabel=f'{title} ({unit})',title=f'({"ac"[row]}) Matched cycle means')
        axes[row,0].legend(frameon=False)
        axes[row,1].plot(x,result['metrics'][key]['cycle_differences'],'-o',ms=3,color='#356BA3')
        axes[row,1].set(xlabel='Global cycle',ylabel=f'High-Tc minus low-Tc ({unit})',title=f'({"bd"[row]}) Paired {title.lower()} response')
    for ax in axes.flat:
        ax.spines[['top','right']].set_visible(False);ax.grid(axis='y',color='#DDDDDD',lw=.5);ax.set_axisbelow(True)
        ax.set_xticks(x[::2]+[x[-1]])
    origin=int(l['boundary_trial']['transition_time_s']/10);start,stop=a['window_s']
    fig.suptitle(f'Same C{origin} complete state | Tc={l["temperature_K"]:.2f} / {h["temperature_K"]:.2f} K | '
        f'common {start:g}-{stop:g} s window',fontsize=12)
    fig.supxlabel('Finite-window response only. No root, asymptotic sensitivity or paired Table 4 endpoint has been established.',fontsize=10)
    figure.parent.mkdir(parents=True,exist_ok=True)
    for suffix in ('.png','.pdf'):fig.savefig(figure.with_suffix(suffix),dpi=280,facecolor='white')
    plt.close(fig)
    figure.with_suffix('.json').write_text(json.dumps(dict(comparison_sha256=sha256(output/'matched_Tc_response.json'),
        png_sha256=sha256(figure.with_suffix('.png')),pdf_sha256=sha256(figure.with_suffix('.pdf'))),indent=2)+'\n',encoding='utf-8')
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('low','high','output','figure'):parser.add_argument('--'+name,required=True,type=Path)
    result=analyze(**vars(parser.parse_args()))
    print(json.dumps({k:v for k,v in result.items() if k not in ('input_sha256','metrics')},indent=2))
    print(json.dumps(result['metrics'],indent=2))

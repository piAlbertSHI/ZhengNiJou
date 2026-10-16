"""Bind the local reference locator to actual PDFs, title pages and page anchors."""
import argparse
import hashlib
import json
import logging
from pathlib import Path
import re
import shutil
import unicodedata

import fitz
import pypdf
from pypdf import PdfReader

from Audit_HeatDriveECC_SegmentedEvidence import sha256


REFERENCES = (
    ('Q01', 'A heat driven elastocaloric cooling system..pdf', '10.1016/j.energy.2019.06.094',
     ['Qian', 'Wang', 'Yuan', 'Yu'], 'primary_2019_quantitative_contract', True,
     [(3, ['\\(1\\)', '\\(2\\)'], None), (4, ['Fig\\.\\s*1', 'Proposed system'], None),
      (5, ['\\(9\\)', '\\(10\\)'], None),
      (17, ['Table\\s*4', '26\\.2', '0\\.64'], None)]),
    ('Q02', 'Thermodynamic cycle analysis of heat driven elastocaloric.pdf', '10.1016/j.energy.2020.117261',
     ['Tan', 'Qian'], 'thermodynamic_coupling_cross_reference', True,
     [(6, ['Mechanical Coupling', 'Displacement'], None), (7, ['full transformation', '\\(5\\)'], None),
      (18, ['Pareto', 'Table\\s*3'], None)]),
    ('Q03', 'Thermodynamics cycle analysis and numerical modeling of thermoelastic cooling systems.pdf',
     '10.1016/j.ijrefrig.2015.04.001', ['Qian', 'Hwang'], 'dynamic_cycle_and_system_boundary', True,
     [(10, ['Cyclic steady state refers', 'repeat the same pattern'], None)]),
    ('Q04', 'Numerical_modeling_of_an_active_elastocaloric_regenerator_refrigerator_with_phase_transformation_kinetics_and_the_matching_principle_for_materials.pdf',
     '10.1016/j.energy.2017.09.116', ['Qian', 'Yuan'], 'kinetics_and_material_matching', True,
     [(6, ['180 s', '10 cycles', 'less than 3%'], None), (9, ['3\\.3\\. Matching principle'], None),
      (10, ['\\(21\\)', '\\(26\\)'], None)]),
    ('Q05', 'Study on high efficient heat recovery cycle for solid-state cooling.pdf',
     '10.1016/j.ijrefrig.2015.03.023', ['Qian', 'Hwang'], 'heat_recovery_and_accessory_inventory', True,
     [(7, ['cyclic steady state', 'connecting pipe'], None), (8, ['ideal heat recovery', 'cyclic steady state'], None)]),
    ('Q06', 'Thermodynamics of elastocaloric cooling and heat pump cycles.pdf',
     '10.1016/j.applthermaleng.2022.119540', ['Qian'], 'ideal_cycle_boundaries', True,
     [(3, ['Table\\s*1', 'Stirling'], None)]),
    ('Q07', 'Cascade utilization of low-grade thermal energy by coupled elastocaloric power and cooling cycle.pdf',
     '10.1016/j.apenergy.2021.117269', ['Qian', 'Wang'], 'power_cooling_cascade_not_2019_topology', True,
     [(4, ['Fig\\.\\s*1', 'Fig\\.\\s*2', 'heat engine cycle'], None)]),
    ('Q08', 'A review of elastocaloric cooling___Materials, cycles and system integrations.pdf',
     '10.1016/j.ijrefrig.2015.12.001', ['Qian', 'Hwang'], 'review_and_system_integration', True,
     [(10, ['Elastocaloric cooling system integration'], None), (17, ['Optimum fluid thermal mass'], None)]),
    ('Q09', 'qian  \u535a\u58eb\u8bba\u6587.pdf', None, ['Suxin Qian', '2015'], 'qian_dissertation', True,
     [(91, ['Chapter\\s*3', 'Cycle Analysis and Dynamic Modeling'], 64),
      (122, ['Chapter\\s*4', 'Thermo-wave Heat Recovery'], 95),
      (158, ['Chapter\\s*5', 'Prototype Design'], 131)]),
    ('A01', 'Modeling_and_analysis_of_an_integrated_solid_state_elastocaloric_heat_pumping_system1.pdf',
     '10.1016/j.energy.2017.05.008', ['Dong Luo', 'Yinshan Feng', 'Parmesh Verma'], 'auxiliary_non_Qian', False,
     [(1, ['Dong Luo', 'Yinshan Feng', 'Parmesh Verma'], None), (5, ['integrated system'], None)]),
)


def normalize(text):
    return ' '.join(unicodedata.normalize('NFKC', text).replace('\x00', '').split())


def identity(text, doi, authors, qian_authored):
    compact=re.sub(r'\s+', '', normalize(text)).lower()
    if doi and doi.lower() not in compact:raise ValueError('Title-page DOI mismatch')
    if any(re.sub(r'\s+', '', a).lower() not in compact for a in authors):
        raise ValueError('Title-page author mismatch')
    declared_qian=any(re.search(r'\bqian\b',a,re.I) is not None for a in authors)
    if declared_qian!=qian_authored:raise ValueError('Authorship classification must follow the checked author list, not body citations')


def page_anchor(text, patterns, printed):
    normalized=normalize(text)
    if any(re.search(p, normalized, re.I) is None for p in patterns):raise ValueError('Page anchor not found')
    if printed is not None and re.match(r'^\s*'+str(printed)+r'\s', text) is None:
        raise ValueError('Printed page does not match the actual page header')
    return dict(patterns=patterns, printed_page=printed, anchor_match=True,
                normalized_text_sha256=hashlib.sha256(normalized.encode('utf-8')).hexdigest().upper())


class WarningCapture(logging.Handler):
    def __init__(self):
        super().__init__(logging.WARNING);self.messages=[]

    def emit(self, record):
        self.messages.append(record.getMessage()[:500])


def build(index, literature_root, output):
    if output.exists():raise FileExistsError('Use a fresh reference evidence directory')
    root=literature_root.resolve()
    paths=list(dict.fromkeys(re.findall(r'C:\\[^`\r\n]+\.pdf',index.read_text(encoding='utf-8'))))
    if len(paths)!=10:raise ValueError('The declared corpus must contain ten distinct local PDFs')
    rows=[]
    for ref, suffix, doi, authors, scope, qian, anchors in REFERENCES:
        candidates=[Path(p).resolve() for p in paths if Path(p).name.endswith(suffix)]
        if len(candidates)!=1:raise ValueError('Ambiguous reference identity: '+ref)
        path=candidates[0];path.relative_to(root)
        capture=WarningCapture();logger=logging.getLogger('pypdf');logger.addHandler(capture)
        try:
            reader=PdfReader(path);pages=len(reader.pages)
            with fitz.open(path) as other:
                if other.page_count!=pages:raise ValueError('Independent page counts disagree: '+ref)
            identity(reader.pages[0].extract_text() or '',doi,authors,qian)
            evidence=[]
            for number, patterns, printed in anchors:
                if not 1<=number<=pages:raise ValueError('Page outside actual PDF: '+ref)
                try:
                    check=page_anchor(reader.pages[number-1].extract_text() or '',patterns,printed)
                except ValueError as error:
                    raise ValueError('PDF page '+str(number)+': '+str(error)) from error
                evidence.append(dict(pdf_page=number,**check))
        except ValueError as error:
            raise ValueError(ref+': '+str(error)) from error
        finally:
            logger.removeHandler(capture)
        rows.append(dict(id=ref,path=str(path),bytes=path.stat().st_size,sha256=sha256(path),
            pdf_pages=pages,cross_parser_page_count_match=True,doi=doi,title_page_authors_checked=authors,
            qian_authored_or_coauthored=qian,scope=scope,anchors=evidence,
            reader_recovery_warnings=capture.messages,source_pdf_modified=False))
    result=dict(schema='heatdrive_ecc_local_reference_locator_v1',reference_count=len(rows),
        qian_documents=sum(r['qian_authored_or_coauthored'] for r in rows),auxiliary_non_Qian_documents=1,
        page_numbers_are_one_based_local_PDF=True,all_title_pages_and_listed_anchors_checked=True,
        full_text_every_page_reviewed=False,zotero_library_searched=False,source_pdf_copied_bytes=0,
        simulation_executed=False,table4_reproduction_claim=False,
        source_index=dict(original_path=str(index.resolve()),path=str((output/'source_index_snapshot.md').resolve()),sha256=sha256(index)),
        producer_script_sha256=sha256(Path(__file__)),producer_script_snapshot=str((output/'producer_source.py').resolve()),
        parser_versions=dict(pypdf=pypdf.__version__,pymupdf=fitz.VersionBind),
        references=rows)
    output.mkdir(parents=True)
    shutil.copyfile(index,output/'source_index_snapshot.md')
    shutil.copyfile(Path(__file__),output/'producer_source.py')
    if sha256(output/'source_index_snapshot.md')!=result['source_index']['sha256']:
        raise ValueError('Changed source index snapshot')
    if sha256(output/'producer_source.py')!=result['producer_script_sha256']:
        raise ValueError('Changed producer source snapshot')
    (output/'reference_locator.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return result


if __name__=='__main__':
    workspace=Path(__file__).resolve().parents[2]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index',type=Path,default=workspace/'项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md')
    parser.add_argument('--literature-root',type=Path,default=workspace.parent/'冷凝文献')
    parser.add_argument('--output',type=Path,required=True)
    r=build(**vars(parser.parse_args()))
    print(json.dumps({k:v for k,v in r.items() if k!='references'},ensure_ascii=False,indent=2))

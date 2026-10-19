"""Rebuild a local readable report without ADB or re-running any case."""
import argparse
import html
import json
from pathlib import Path
from run import build_report, read_journal, classified_stage

def render(folder):
    report = build_report(folder)
    rows, _ = read_journal(folder / 'results.jsonl', [])
    summary = report['summary']
    display = lambda value: 'unknown' if value is None else str(value)
    counts = {k: report[k] for k in ('planned', 'started', 'completed', 'unknown', 'unattempted', 'remaining_without_result')}
    text = ['# Parser QA comparison', '',
        'Exploratory debug/emulator data. Timings cover successful stages only. PSS is a sampled sum of identifiable processes, excluding shared services. Not a TV or long-run acceptance.', '',
        'Coverage: ' + '; '.join(f'{k}={display(v)}' for k, v in counts.items()) + '.',
        'Missing old plan/start data remains unknown. Completed means a durable result record; unknown means a started attempt without a terminal result.', '',
        '| Group | Engine | Recorded attempts | Invalid environment | Eligible results | Resolved | First frame | Resolve median ms | Frame median ms | Peak PSS median MiB |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for r in summary:
        text.append('| ' + ' | '.join(display(r[k]) for k in ('group','engine','attempted','invalid','eligible_results','resolved','first_frame','resolve_median_ms','frame_median_ms','sampled_peak_pss_median_mib')) + ' |')
    text += ['', '| Case | Repeat | Engine | Outcome | Episode page SHA256 |', '| --- | ---: | --- | --- | --- |']
    for r in rows:
        text.append(f"| {r['id']} | {r.get('repeat', 0)} | {r['engine']} | {classified_stage(r)} | {r.get('episode_page_sha256', 'not reached')} |")
    text += ['', '| Planned or observed case | Engine | Repeat | Execution state | Key |', '| --- | --- | ---: | --- | --- |']
    for r in report['case_states']:
        text.append('| ' + ' | '.join(display(r[k]) for k in ('id', 'engine', 'repeat', 'state', 'key')) + ' |')
    text += ['', 'Raw stage/error_type remain unchanged in results.jsonl. Environment invalidity takes priority and is excluded from product metrics. Engine pairs with different episode hashes must not be treated as matched-page comparisons.', '',
             'Run/cleanup status: ' + json.dumps(report['run_status'], ensure_ascii=False),
             'Journal issues: ' + json.dumps(report['journal_issues'], ensure_ascii=False), '']
    (folder / 'comparison.md').write_text('\n'.join(text), encoding='utf-8')
    # Use escaped tables rather than interpolating untrusted source titles as HTML.
    tables = []
    for values in [summary, [{'case': r['id'], 'engine': r['engine'], 'outcome': classified_stage(r),
                             'repeat': r.get('repeat', 0)} for r in rows], report['case_states']]:
        if not values:
            continue
        headers = list(values[0])
        tables.append('<table><tr>' + ''.join('<th>'+html.escape(h)+'</th>' for h in headers) + '</tr>' +
            ''.join('<tr>'+''.join('<td>'+html.escape(display(r[h]))+'</td>' for h in headers)+'</tr>' for r in values)+'</table>')
    (folder / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    (folder / 'report.html').write_text('<meta charset="utf-8"><title>Parser QA</title><style>body{font:15px system-ui;margin:32px;background:#16181d;color:#eee}table{border-collapse:collapse;margin:24px 0}td,th{border:1px solid #555;padding:8px;text-align:left}th{background:#29303d}</style><h1>Parser QA comparison</h1><p>Debug / emulator / sampled PSS. Invalid environments excluded from product metrics. Missing coverage remains unknown.</p><p>' + html.escape('; '.join(f'{k}={display(v)}' for k, v in counts.items())) + '</p>' + ''.join(tables) + '<pre>' + html.escape(json.dumps({'run_status': report['run_status'], 'journal_issues': report['journal_issues']}, ensure_ascii=False, indent=2)) + '</pre>', encoding='utf-8')
    return report

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder', type=Path)
    print(json.dumps(render(p.parse_args().folder), ensure_ascii=False, indent=2))

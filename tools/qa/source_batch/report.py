"""Rebuild a local readable report without ADB or re-running any case."""
import argparse
import html
import json
from pathlib import Path
from run import summarize, classified_stage

def render(folder):
    rows = [json.loads(line) for line in (folder / 'results.jsonl').read_text(encoding='utf-8').splitlines()]
    summary = summarize(rows)
    text = ['# Parser QA comparison', '',
        'Exploratory debug/emulator data. Timings cover successful stages only. PSS is a sampled sum of identifiable processes, excluding shared services. Not a TV or long-run acceptance.', '',
        '| Group | Engine | Attempts | Resolved | First frame | Resolve median ms | Frame median ms | Peak PSS median MiB |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for r in summary:
        text.append('| ' + ' | '.join(str(r[k]) for k in ('group','engine','attempted','resolved','first_frame','resolve_median_ms','frame_median_ms','sampled_peak_pss_median_mib')) + ' |')
    text += ['', '| Case | Repeat | Engine | Outcome | Episode page SHA256 |', '| --- | ---: | --- | --- | --- |']
    for r in rows:
        text.append(f"| {r['id']} | {r.get('repeat', 0)} | {r['engine']} | {classified_stage(r)} | {r.get('episode_page_sha256', 'not reached')} |")
    text += ['', 'Raw stage/error_type remain unchanged in results.jsonl. VideoSourceTimeoutException is classified as resolve_timeout. Engine pairs with different episode hashes must not be treated as matched-page comparisons.', '']
    (folder / 'comparison.md').write_text('\n'.join(text), encoding='utf-8')
    # Use escaped tables rather than interpolating untrusted source titles as HTML.
    tables = []
    for values in [summary, [{'case': r['id'], 'engine': r['engine'], 'outcome': classified_stage(r),
                             'repeat': r.get('repeat', 0)} for r in rows]]:
        if not values:
            continue
        headers = list(values[0])
        tables.append('<table><tr>' + ''.join('<th>'+html.escape(h)+'</th>' for h in headers) + '</tr>' +
            ''.join('<tr>'+''.join('<td>'+html.escape(str(r[h]))+'</td>' for h in headers)+'</tr>' for r in values)+'</table>')
    (folder / 'report.html').write_text('<meta charset="utf-8"><title>Parser QA</title><style>body{font:15px system-ui;margin:32px;background:#16181d;color:#eee}table{border-collapse:collapse;margin:24px 0}td,th{border:1px solid #555;padding:8px;text-align:left}th{background:#29303d}</style><h1>Parser QA comparison</h1><p>Debug / emulator / sampled PSS. Successful-stage medians only. No TV compatibility claim.</p>' + ''.join(tables), encoding='utf-8')
    return summary

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder', type=Path)
    print(json.dumps(render(p.parse_args().folder), ensure_ascii=False, indent=2))

"""Aggregate public GitHub release downloads; snapshots never leave this machine."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import urllib.request
from zoneinfo import ZoneInfo

REPO = 'AbdullahNazih/LumaPulse'

def app_asset(name):
    name = name.lower()
    return name.startswith('lumapulse-') and name.endswith(('.zip', '.dmg', '.pkg'))

def fetch_releases():
    releases = []
    for page in range(1, 101):
        request = urllib.request.Request(f'https://api.github.com/repos/{REPO}/releases?per_page=100&page={page}', headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'LumaPulse-download-report', 'X-GitHub-Api-Version': '2022-11-28'})
        with urllib.request.urlopen(request, timeout=25) as response:
            data = response.read(4_194_305)
        if len(data) > 4_194_304:
            raise ValueError('GitHub response exceeds report size limit')
        batch = json.loads(data)
        if not isinstance(batch, list):
            raise ValueError('GitHub returned an unexpected response')
        releases.extend(batch)
        if len(batch) < 100:
            return releases
    raise ValueError('Pagination incomplete; baseline was not changed')

def snapshot(releases, observed_at):
    assets = {}
    for release in releases:
        if release.get('draft'):
            continue
        for asset in release.get('assets', []):
            if app_asset(asset['name']):
                count = asset['download_count']
                if not isinstance(count, int) or count < 0:
                    raise ValueError('Invalid download count')
                assets[str(asset['id'])] = {'version': release['tag_name'], 'name': asset['name'], 'count': count}
    return {'repository': REPO, 'observed_at': observed_at, 'assets': assets}

def compare(current, previous):
    assets = current['assets']
    result = {'total': sum(asset['count'] for asset in assets.values()), 'increase': None, 'removed': [], 'reset': [], 'assets': assets}
    if previous is None:
        return result
    if previous.get('repository') != REPO or not isinstance(previous.get('assets'), dict):
        raise ValueError('Snapshot does not belong to this repository')
    older = previous['assets']
    result['removed'] = [older[key]['name'] for key in older.keys() - assets.keys()]
    result['reset'] = [asset['name'] for key, asset in assets.items() if key in older and asset['count'] < older[key]['count']]
    result['increase'] = sum(max(0, asset['count'] - older.get(key, {'count': 0})['count']) for key, asset in assets.items())
    return result

def write_snapshot(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile('w', dir=path.parent, delete=False, prefix='.downloads-') as handle:
            temporary = Path(handle.name)
            json.dump(data, handle, indent=2)
            handle.flush(); os.fsync(handle.fileno())
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--snapshot', type=Path, default=Path(__file__).resolve().parents[1] / '.reports/downloads.json')
    args = parser.parse_args()
    previous = json.loads(args.snapshot.read_text()) if args.snapshot.exists() else None
    now = dt.datetime.now(dt.timezone.utc)
    current = snapshot(fetch_releases(), now.isoformat())
    result = compare(current, previous)
    write_snapshot(args.snapshot, current)
    print('LumaPulse download report · ' + now.astimezone(ZoneInfo('Asia/Kuwait')).strftime('%Y-%m-%d %H:%M Kuwait'))
    print(f"Total app-package downloads: {result['total']}")
    print('Baseline established; daily increase is not yet available.' if result['increase'] is None else f"Observed increase since last successful check: +{result['increase']}")
    if previous:
        print('Previous successful observation: ' + previous['observed_at'])
    for asset in sorted(result['assets'].values(), key=lambda item: (item['version'], item['name'])):
        print(f"- {asset['version']} · {asset['name']}: {asset['count']}")
    if result['removed']:
        print('Assets missing or replaced: ' + ', '.join(result['removed']))
    if result['reset']:
        print('Counters decreased; inspect replacements: ' + ', '.join(result['reset']))
    print('Counts represent downloads, not unique users. https://github.com/' + REPO + '/releases')

if __name__ == '__main__':
    main()

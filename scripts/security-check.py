"""Deterministic source and packaged-app gates; no network access."""
import argparse
import pathlib
import plistlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]

def check_sources():
    ignored = {'.git', '.build', 'dist', '.reports', '__pycache__'}
    secret = re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{35,}|AKIA[0-9A-Z]{16}|bz\.production[A-Za-z0-9_-]{20,}')
    for path in ROOT.rglob('*'):
        if not path.is_file() or any(p in ignored for p in path.relative_to(ROOT).parts):
            continue
        assert path.suffix.lower() not in {'.p12', '.pfx', '.pem', '.key', '.mobileprovision'}, f'Credential file: {path.name}'
        assert not path.name.startswith('.env'), f'Environment file: {path.name}'
        try:
            content = path.read_text()
        except (UnicodeError, OSError):
            continue
        assert not secret.search(content), f'Possible secret in {path.relative_to(ROOT)}'
        if path.suffix in {'.yml', '.yaml'} and '.github' in path.parts:
            assert 'pull_request_target' not in content, 'Privileged PR trigger is forbidden'
            for action in re.findall(r'uses:\s*([^\s#]+)', content):
                assert re.fullmatch(r'[^@]+@[a-f0-9]{40}', action), f'Action must be SHA-pinned: {action}'
            if '/workflows/' in str(path):
                assert 'permissions:' in content and 'timeout-minutes:' in content
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.anazih.lumapulse'
    assert 'NSAppTransportSecurity' not in info, 'ATS exceptions forbidden'
    entitlements = plistlib.loads((ROOT / 'Resources/LumaPulse.entitlements').read_bytes())
    assert entitlements == {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True,
                            'com.apple.security.files.user-selected.read-write': True}
    for file in (ROOT / 'Sources').rglob('*.swift'):
        source = file.read_text()
        assert 'serverTrust' not in source and 'URLCredential(trust:' not in source, 'Custom certificate trust bypass'
        assert not re.search(r'Process\s*\(', source), 'App must not execute shell commands'

def check_app(path, mode):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True)
    details = subprocess.run(['codesign', '-dv', '--verbose=4', str(path)], capture_output=True, text=True, check=True).stderr
    assert 'runtime' in details, 'Hardened runtime missing'
    data = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)], capture_output=True, check=True).stdout
    assert plistlib.loads(data) == {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True,
                            'com.apple.security.files.user-selected.read-write': True}
    if mode == 'distribution':
        assert 'Authority=Developer ID Application:' in details and 'Timestamp=' in details
    for file in path.rglob('*'):
        assert file.suffix.lower() not in {'.p12', '.pfx', '.pem', '.key'}, 'Credential bundled in app'

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=pathlib.Path)
    parser.add_argument('--mode', choices=['local', 'distribution'], default='local')
    args = parser.parse_args()
    check_sources()
    if args.app:
        check_app(args.app, args.mode)
    print('Security gates passed' + (' including packaged protections' if args.app else ''))

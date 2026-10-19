#!/usr/bin/env python3
"""Export an allowlisted committed snapshot, without private deployment history.

The destination must not exist. No Git history, state, credentials, device
backups or personal release records are copied. Review the result before push.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

BASE = Path(__file__).resolve().parents[1]
ROOTS = {'.gitignore', 'LICENSE', 'README.md', 'config', 'conversations.py',
         'desk.py', 'math_text.py', 'mac_metrics.py', 'panel_render.py', 'requirements.txt',
         'requirements.lock', 'panel', 'kindle', 'mac', 'scripts', 'tests',
         'vendor', 'docs', 'examples', '.github'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--ref', default='HEAD')
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=False)
    raw = subprocess.check_output(['git', '-C', str(BASE), 'archive', args.ref])
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        members = [m for m in archive.getmembers() if Path(m.name).parts[0] in ROOTS]
        archive.extractall(args.destination, members=members, filter='data')
    files = {str(p.relative_to(args.destination)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(args.destination.rglob('*')) if p.is_file()}
    manifest = {'format': 1, 'description': 'Reviewed source export without personal deployment history', 'files': files}
    (args.destination / 'SOURCE_MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Exported {len(files)} files to {args.destination}')


if __name__ == '__main__':
    main()

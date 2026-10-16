#!/usr/bin/env python3
"""Create Chinese and English source archives from a committed snapshot."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

BASE = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ref', default='HEAD')
parser.add_argument('--output', type=Path, default=BASE/'dist')
args = parser.parse_args()
sha = subprocess.check_output(['git', '-C', str(BASE), 'rev-parse', args.ref], text=True).strip()
args.output.mkdir(parents=True, exist_ok=True)
checksums = []
for language in ('zh', 'en'):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)/'kindle-desk'
        subprocess.run([sys.executable, str(BASE/'scripts/export-public.py'), str(root), '--ref', sha], check=True)
        config = root/'config/example.json'
        value = json.loads(config.read_text()); value['language'] = language
        config.write_text(json.dumps(value, indent=2)+'\n')
        (root/'EDITION.json').write_text(json.dumps({'language':language,'source_commit':sha,'package_type':'source'},indent=2)+'\n')
        manifest = root/'SOURCE_MANIFEST.json'
        files = {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in sorted(root.rglob('*')) if p.is_file() and p != manifest}
        manifest.write_text(json.dumps({'format':1,'files':files},indent=2)+'\n')
        output = args.output/f'kindle-desk-{language}.zip'
        with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
            for p in sorted(root.rglob('*')):
                if p.is_file():
                    info=zipfile.ZipInfo('kindle-desk/'+str(p.relative_to(root)),date_time=(2026,1,1,0,0,0))
                    info.compress_type=zipfile.ZIP_DEFLATED; info.external_attr=0o100644 << 16
                    archive.writestr(info,p.read_bytes())
        checksums.append(hashlib.sha256(output.read_bytes()).hexdigest()+'  '+output.name)
(args.output/'SHA256SUMS.txt').write_text('\n'.join(checksums)+'\n')
print('\n'.join(checksums))

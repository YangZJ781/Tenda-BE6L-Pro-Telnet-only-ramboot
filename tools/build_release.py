"""Reproduce the standalone PS1 from the exact payload archive in a Release."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def validate_payload(data, lock, manifest):
    if sha256(data) != lock['payload_sha256']:
        raise ValueError('Payload archive SHA256 mismatch')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        embedded = json.loads(archive.read('manifest.json'))
        if embedded != manifest:
            raise ValueError('Embedded manifest differs from the repository manifest')
        expected = {'manifest.json'} | {item['local'] for item in manifest['files']}
        if set(archive.namelist()) != expected or len(archive.namelist()) != len(expected):
            raise ValueError('Unexpected or duplicate archive entries')
        for item in manifest['files']:
            content = archive.read(item['local'])
            if len(content) != item['size'] or sha256(content) != item['sha256']:
                raise ValueError('Payload mismatch: ' + item['local'])


def build_script(template, payload, lock, manifest):
    validate_payload(payload, lock, manifest)
    if template.count('__PAYLOAD_SHA256__') != 1 or template.count('__PAYLOAD_BASE64__') != 1:
        raise ValueError('Expected exactly one placeholder of each kind')
    source = template.replace('__PAYLOAD_SHA256__', sha256(payload))
    source = source.replace('__PAYLOAD_BASE64__', base64.encodebytes(payload).decode('ascii').rstrip())
    return b'\xef\xbb\xbf' + source.encode('utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--payload', type=Path, default=ROOT / 'dist/ramboot-payloads.zip')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    parser.add_argument('--verify-release', action='store_true')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'payloads/lock.json').read_text(encoding='utf-8'))
    manifest = json.loads((ROOT / 'payloads/manifest.json').read_text(encoding='utf-8'))
    template = (ROOT / 'src/Start-BE6L-Ramboot.template.ps1').read_text(encoding='utf-8-sig')
    payload = args.payload.read_bytes()
    script = build_script(template, payload, lock, manifest)
    digest = sha256(script)
    if args.verify_release and digest != lock['script_sha256']:
        raise ValueError('Generated script is not byte-identical to the hardware-tested release')
    args.output.mkdir(parents=True, exist_ok=True)
    target = args.output / 'Start-BE6L-Ramboot.ps1'
    target.write_bytes(script)
    archive = args.output / 'BE6L-Pro-RAM-Boot.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        info = zipfile.ZipInfo(target.name, (2026, 10, 19, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, script, compresslevel=9)
    payload_copy = args.output / 'ramboot-payloads.zip'
    if args.payload.resolve() != payload_copy.resolve():
        shutil.copyfile(args.payload, payload_copy)
    files = [target, archive, payload_copy]
    (args.output / 'SHA256SUMS').write_text(''.join(sha256(p.read_bytes())+'  '+p.name+'\n' for p in files), encoding='ascii')
    print('Built:', target)
    print('SHA256:', digest)
    print('Matches hardware-tested script:', digest == lock['script_sha256'])


if __name__ == '__main__':
    main()

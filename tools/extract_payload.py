"""Recover and verify the payload ZIP embedded in a standalone PS1."""
import argparse
import base64
import hashlib
import re
from pathlib import Path


def extract(script):
    match = re.search(r"(?ms)^\$script:EmbeddedZipSHA256 = '([0-9a-f]{64})'\n\$script:EmbeddedZip = @'\n(.*?)\n'@", script)
    if not match:
        raise ValueError('No recognized embedded payload')
    data = base64.b64decode(match.group(2))
    if hashlib.sha256(data).hexdigest() != match.group(1):
        raise ValueError('Embedded payload checksum mismatch')
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('script', type=Path)
    parser.add_argument('--output', type=Path, default=Path('ramboot-payloads.zip'))
    args = parser.parse_args()
    data = extract(args.script.read_text(encoding='utf-8-sig'))
    args.output.write_bytes(data)
    print('Verified payload ZIP:', args.output)


if __name__ == '__main__':
    main()

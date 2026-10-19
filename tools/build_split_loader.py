"""Build a minimal static ARM EABI kexec_load helper for verified RAM segments.

Uses open/mmap2/kexec_load/exit only. The kernel image bytes are unchanged.
The first segment ends at the vendor memblock boundary at 0x80200000.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct

root = Path(__file__).resolve().parent.parent / '.payloads'
parser = argparse.ArgumentParser()
parser.add_argument('--disable-wifi', action='store_true')
args = parser.parse_args()
be32 = lambda b, o=0: struct.unpack_from('>I', b, o)[0]
kernel = (root / 'openwrt-kernel').read_bytes()
dtb = (root / 'openwrt.dtb').read_bytes()
struct_start, strings_start = be32(dtb, 8), be32(dtb, 12)
strings = dtb[strings_start:strings_start + be32(dtb, 32)]
pos = struct_start
stack = []
out = bytearray()
changed = []
while True:
    start = pos
    token = be32(dtb, pos)
    pos += 4
    if token == 1:
        end = dtb.index(0, pos)
        stack.append(dtb[pos:end].decode())
        pos = (end + 4) & ~3
    elif token == 2:
        stack.pop()
    elif token == 3:
        length, nameoff = struct.unpack_from('>II', dtb, pos)
        name = strings[nameoff:strings.index(0, nameoff)].decode()
        pos += 8
        value = dtb[pos:pos + length]
        pos = (pos + length + 3) & ~3
        replace = False
        if stack == ['', 'chosen'] and name in ('bootargs', 'bootargs-override'):
            changed.append({'path': '/'.join(stack), 'property': name, 'old': value.rstrip(b'\0').decode()})
            value = b'console=ttyS0,115200 earlycon\0'
            replace = True
        elif args.disable_wifi and stack == ['', 'soc', 'pcie@1fa91000'] and name == 'status':
            changed.append({'path': '/'.join(stack), 'property': name, 'old': value.rstrip(b'\0').decode(), 'new': 'disabled'})
            value = b'disabled\0'
            replace = True
        if replace:
            out.extend(struct.pack('>III', 3, len(value), nameoff))
            out.extend(value)
            out.extend(b'\0' * (-len(value) % 4))
            continue
    elif token not in (4, 9):
        raise ValueError(token)
    out.extend(dtb[start:pos])
    if token == 9:
        break
assert changed
new_dtb = bytearray(dtb[:struct_start]) + out + strings
struct.pack_into('>I', new_dtb, 4, len(new_dtb))
struct.pack_into('>I', new_dtb, 12, struct_start + len(out))
struct.pack_into('>I', new_dtb, 36, len(out))
(root / 'openwrt-ramonly.dtb').write_bytes(new_dtb)

base = 0x10000
code_offset = 0x100
words = []
labels = {}
fixups = []
data = bytearray()
data_labels = {}

def emit(word):
    words.append(word)

def label(name):
    labels[name] = base + code_offset + len(words) * 4

def literal(reg, value):
    fixups.append(('literal', len(words), reg, value))
    emit(0)

def branch(cond, target):
    fixups.append(('branch', len(words), cond, target))
    emit(0)

def mov(reg, value):
    assert 0 <= value <= 255
    emit(0xe3a00000 | reg << 12 | value)

def syscall(number):
    if number < 256:
        mov(7, number)
    else:
        literal(7, number)
    emit(0xef000000)

def check_error():
    literal(6, 0xfffff001)
    emit(0xe1500006)  # cmp r0,r6
    branch(2, 'error')  # bhs error

def open_map(path, length):
    literal(0, path)
    mov(1, 0)
    mov(2, 0)
    syscall(5)  # open
    check_error()
    emit(0xe1a04000)  # mov r4,r0 (fd)
    mov(0, 0)
    literal(1, length)
    mov(2, 1)  # PROT_READ
    mov(3, 2)  # MAP_PRIVATE
    mov(5, 0)
    syscall(192)  # mmap2
    check_error()

label('start')
open_map('kernel_path', len(kernel))
literal(1, 'segments')
emit(0xe5810000)  # str r0,[r1]
literal(2, 0x178000)
emit(0xe0800002)  # add r0,r0,r2
emit(0xe5810010)  # str r0,[r1,#16]
open_map('dtb_path', len(new_dtb))
literal(1, 'segments')
emit(0xe5810020)  # str r0,[r1,#32]
literal(0, 0x80088000)
mov(1, 3)
literal(2, 'segments')
literal(3, 0x280000)  # KEXEC_ARCH_ARM
syscall(347)  # kexec_load, ARM EABI
check_error()
mov(0, 0)
syscall(1)
label('error')
emit(0xe2600000)  # rsb r0,r0,#0 (errno as exit status)
syscall(1)

def add_data(name, b):
    data.extend(b'\0' * (-len(data) % 4))
    data_labels[name] = len(data)
    data.extend(b)

add_data('kernel_path', b'/tmp/cdx-ramboot/openwrt-kernel\0')
add_data('dtb_path', b'/tmp/cdx-ramboot/openwrt-ramonly.dtb\0')
first = 0x178000
remaining = len(kernel) - first
segments = [(0, first, 0x80088000, first),
            (0, remaining, 0x80200000, (remaining + 4095) & ~4095),
            (0, len(new_dtb), 0x86ee3000, (len(new_dtb) + 4095) & ~4095)]
add_data('segments', b''.join(struct.pack('<IIII', *s) for s in segments))
for kind, index, reg, value in fixups:
    if kind == 'literal':
        data.extend(b'\0' * (-len(data) % 4))
        literal_address = base + code_offset + len(words) * 4 + len(data)
        if isinstance(value, str):
            value = base + code_offset + len(words) * 4 + data_labels[value]
        data.extend(struct.pack('<I', value))
        delta = literal_address - (base + code_offset + index * 4 + 8)
        assert 0 <= delta <= 4095
        words[index] = 0xe59f0000 | reg << 12 | delta
    else:
        delta = (labels[value] - (base + code_offset + index * 4 + 8)) // 4
        words[index] = reg << 28 | 0x0a000000 | delta & 0xffffff
payload = b''.join(struct.pack('<I', w) for w in words) + data
size = code_offset + len(payload)
ident = b'\x7fELF\x01\x01\x01' + b'\0' * 9
header = ident + struct.pack('<HHIIIIIHHHHHH', 2, 40, 1, base + code_offset,
                            52, 0, 0x5000200, 52, 32, 1, 0, 0, 0)
phdr = struct.pack('<IIIIIIII', 1, 0, base, base, size, size, 7, 4096)
binary = header + phdr
binary += b'\0' * (code_offset - len(binary)) + payload
(root / 'kexec-split-loader').write_bytes(binary)
(root / 'split-loader-manifest.json').write_text(json.dumps({
    'loader_sha256': hashlib.sha256(binary).hexdigest(),
    'kernel_sha256': hashlib.sha256(kernel).hexdigest(),
    'dtb_changes': changed, 'new_bootargs': 'console=ttyS0,115200 earlycon',
    'entry': '0x80088000', 'segments': segments,
    'syscalls': {'open': 5, 'mmap2': 192, 'kexec_load': 347, 'exit': 1}
}, indent=2), encoding='utf-8')
print('Loader:', len(binary), 'DTB:', len(new_dtb), 'segments:', segments)


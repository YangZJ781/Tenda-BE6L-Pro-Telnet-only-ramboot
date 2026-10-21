"""Read selected files from this device's Tenda/XZ SquashFS, without mounting.

The vendor changes the XZ stream signature/checksums. Decode the LZMA2
payload directly; callers must verify the input and extracted files separately.
Only regular files and directories used for research are supported.
"""
import argparse
from functools import lru_cache
import lzma
from pathlib import Path
import struct


class SquashFS:
    def __init__(self, data):
        self.data = data
        header = struct.unpack_from('<5I6H8Q', data)
        if data[:4] not in (b'nice', b'hsqs') or header[5] != 4 or header[9:11] != (4, 0):
            raise ValueError('Expected SquashFS 4 / XZ')
        self.block_size, self.fragment_count = header[3:5]
        self.root, self.bytes_used = header[11:13]
        self.inodes, self.directories, self.fragments = header[15:18]
        if self.bytes_used > len(data):
            raise ValueError('Truncated filesystem')

    @staticmethod
    def decompress(data):
        if data.startswith(b'\xfd7zXZ\x00'):
            return lzma.decompress(data)
        if not data.startswith(b'Tenda'):
            raise ValueError('Unknown compressed block')
        # XZ stream header (12), block header ((size + 1) * 4), raw LZMA2.
        offset = 12 + (data[12] + 1) * 4
        decoder = lzma.LZMADecompressor(format=lzma.FORMAT_RAW,
            filters=[{'id': lzma.FILTER_LZMA2, 'dict_size': 64 * 1024 * 1024}])
        result = decoder.decompress(data[offset:])
        if not decoder.eof:
            raise ValueError('Truncated LZMA2 block')
        return result

    @lru_cache(maxsize=256)
    def metadata(self, position):
        size, = struct.unpack_from('<H', self.data, position)
        length = size & 0x7fff
        block = self.data[position+2:position+2+length]
        result = block if size & 0x8000 else self.decompress(block)
        if len(result) > 8192:
            raise ValueError('Invalid metadata length')
        return result, position + 2 + length

    def meta_read(self, position, offset, size):
        result = bytearray()
        while len(result) < size:
            block, following = self.metadata(position)
            if offset > len(block):
                raise ValueError('Invalid metadata offset')
            result.extend(block[offset:offset+size-len(result)])
            position, offset = following, 0
            if not block:
                raise ValueError('Empty metadata')
        return bytes(result)

    def inode(self, reference):
        pos, off = self.inodes + (reference >> 16), reference & 0xffff
        raw = self.meta_read(pos, off, 32)
        kind, = struct.unpack_from('<H', raw)
        return kind, raw, pos, off

    def children(self, reference):
        kind, raw, _, _ = self.inode(reference)
        if kind != 1:
            raise ValueError('Expected a basic directory inode')
        start, _, size, offset, _ = struct.unpack_from('<IIHHI', raw, 16)
        data = self.meta_read(self.directories + start, offset, size - 3)
        cursor = 0
        while cursor < len(data):
            count, inode_block, _ = struct.unpack_from('<III', data, cursor)
            cursor += 12
            if count > 255:
                raise ValueError('Invalid directory count')
            for _ in range(count + 1):
                inode_offset, _, _, name_size = struct.unpack_from('<HhHH', data, cursor)
                cursor += 8
                name = data[cursor:cursor+name_size+1].decode()
                cursor += name_size + 1
                yield name, (inode_block << 16) | inode_offset

    def read(self, path):
        reference = self.root
        for part in path.strip('/').split('/'):
            reference = dict(self.children(reference))[part]
        kind, raw, position, offset = self.inode(reference)
        if kind != 2:
            raise ValueError('Expected a basic regular file inode')
        start, fragment, fragment_offset, length = struct.unpack_from('<IIII', raw, 16)
        blocks = length // self.block_size + (fragment == 0xffffffff and bool(length % self.block_size))
        sizes = self.meta_read(position, offset+32, blocks*4) if blocks else b''
        result = bytearray()
        for (size,) in struct.iter_unpack('<I', sizes):
            if size == 0:
                result.extend(b'\0' * self.block_size)
                continue
            packed = self.data[start:start+(size & 0xffffff)]
            result.extend(packed if size & 0x1000000 else self.decompress(packed))
            start += size & 0xffffff
        if fragment != 0xffffffff and length % self.block_size:
            table, = struct.unpack_from('<Q', self.data, self.fragments+(fragment//512)*8)
            entry = self.meta_read(table, (fragment%512)*16, 16)
            start, size, _ = struct.unpack('<QII', entry)
            packed = self.data[start:start+(size & 0xffffff)]
            content = packed if size & 0x1000000 else self.decompress(packed)
            result.extend(content[fragment_offset:fragment_offset+length%self.block_size])
        if len(result) != length:
            raise ValueError('Extracted file length mismatch')
        return bytes(result)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('path')
    parser.add_argument('output', type=Path)
    parser.add_argument('--offset', type=int, default=0)
    args = parser.parse_args()
    args.output.write_bytes(SquashFS(args.input.read_bytes()[args.offset:]).read(args.path))
    print(args.output, args.output.stat().st_size)

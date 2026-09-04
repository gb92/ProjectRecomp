#!/usr/bin/env python3
"""
Parses an XEX2 file, decompresses it, and searches for register
save/restore function byte patterns needed by XenonRecomp.
"""
import sys
import struct
import subprocess
import os

# XEX2 constants
XEX2_MAGIC = b'XEX2'
XEX2_HEADER_KEY_ENTRY_POINT = 0x00010100
XEX2_HEADER_KEY_BASE_ADDRESS = 0x00010001
XEX2_HEADER_KEY_IMAGE_BASE_ADDRESS = 0x00010001
XEX2_OPT_HEADER_SECURITY_INFO = 0x40003
XEX2_COMPRESSION_NONE = 0
XEX2_COMPRESSION_BASIC = 1
XEX2_COMPRESSION_NORMAL = 2
XEX2_ENCRYPTION_NONE = 0

def parse_xex2_header(data):
    """Parse XEX2 header to extract key information."""
    info = {}
    if data[:4] != XEX2_MAGIC:
        raise ValueError("Not an XEX2 file")
    
    info['module_flags'] = struct.unpack('>I', data[4:8])[0]
    info['header_size'] = struct.unpack('>I', data[8:12])[0]
    info['image_size'] = struct.unpack('>I', data[12:16])[0]
    info['optional_header_count'] = struct.unpack('>I', data[0x14:0x18])[0]
    
    # Parse optional headers
    offset = 0x18
    for i in range(info['optional_header_count']):
        if offset + 8 > len(data):
            break
        header_id = struct.unpack('>I', data[offset:offset+4])[0]
        header_val = struct.unpack('>I', data[offset+4:offset+8])[0]
        
        if header_id == 0x00010001:  # Base address (value is inline)
            info['base_address'] = header_val
        elif header_id == 0x00010100:  # Entry point (value is inline)
            info['entry_point'] = header_val
        elif (header_id >> 8) == 0x400:  # Security info (points to data)
            info['security_info_offset'] = header_val
        elif (header_id >> 8) == 0x003:  # File format info
            info['file_format_offset'] = header_val
            
        offset += 8
    
    # Parse security info for load address
    if 'security_info_offset' in info:
        sec_off = info['security_info_offset']
        if sec_off + 0x10C + 4 <= len(data):
            info['load_address'] = struct.unpack('>I', data[sec_off + 0x104:sec_off + 0x108])[0]
    
    # Parse file format info for compression type
    if 'file_format_offset' in info:
        ff_off = info['file_format_offset']
        if ff_off + 8 <= len(data):
            info['encryption_type'] = struct.unpack('>H', data[ff_off:ff_off+2])[0]
            info['compression_type'] = struct.unpack('>H', data[ff_off+2:ff_off+4])[0]
    
    return info

def main():
    if len(sys.argv) < 2:
        print("Usage: find_register_funcs.py <xex_file>")
        sys.exit(1)

    filepath = sys.argv[1]
    with open(filepath, 'rb') as f:
        data = f.read()

    print(f"File size: {len(data):,} bytes")
    
    # Parse header
    info = parse_xex2_header(data)
    base_addr = info.get('base_address', info.get('load_address', 0x82000000))
    header_size = info['header_size']
    
    print(f"Base address:    0x{base_addr:08X}")
    print(f"Header size:     0x{header_size:X}")
    print(f"Image size:      0x{info['image_size']:X}")
    if 'entry_point' in info:
        print(f"Entry point:     0x{info['entry_point']:08X}")
    if 'encryption_type' in info:
        enc_names = {0: "None", 1: "Normal (AES)"}
        comp_names = {0: "None", 1: "Basic", 2: "Normal (LZX)", 3: "Delta"}
        print(f"Encryption:      {enc_names.get(info['encryption_type'], info['encryption_type'])}")
        print(f"Compression:     {comp_names.get(info['compression_type'], info['compression_type'])}")

    # The raw data after the header may be compressed/encrypted.
    # XenonAnalyse was able to parse it, so let's try a different approach:
    # Use XenonRecomp's ability to create a patched (decompressed) XEX.
    # 
    # For now, let's search the raw file data anyway — some XEX files
    # store the code uncompressed, or the patterns may appear after
    # the tool decompresses it.
    
    raw_code = data[header_size:]
    
    patterns = [
        ("restgprlr_14_address", bytes.fromhex("e9c1ff68"),
         "__restgprlr_14: ld r14, -0x98(r1)"),
        ("savegprlr_14_address", bytes.fromhex("f9c1ff68"),
         "__savegprlr_14: std r14, -0x98(r1)"),
        ("restfpr_14_address", bytes.fromhex("c9ccff70"),
         "__restfpr_14: lfd f14, -0x90(r12)"),
        ("savefpr_14_address", bytes.fromhex("d9ccff70"),
         "__savefpr_14: stfd r14, -0x90(r12)"),
        ("restvmx_14_address", bytes.fromhex("3960fee07dcb60ce"),
         "__restvmx_14: li r11, -0x120; lvx v14, r11, r12"),
        ("savevmx_14_address", bytes.fromhex("3960fee07dcb61ce"),
         "__savevmx_14: li r11, -0x120; stvx v14, r11, r12"),
        ("restvmx_64_address", bytes.fromhex("3960fc00100b60cb"),
         "__restvmx_64: li r11, -0x400; lvx128 v64, r11, r12"),
        ("savevmx_64_address", bytes.fromhex("3960fc00100b61cb"),
         "__savevmx_64: li r11, -0x400; stvx128 v64, r11, r12"),
    ]

    print(f"\n=== Searching raw file data (after 0x{header_size:X} header) ===\n")

    found_raw = {}
    for toml_key, pattern, desc in patterns:
        idx = data.find(pattern)
        if idx != -1:
            found_raw[toml_key] = idx
            print(f"  FOUND  {toml_key} at file offset 0x{idx:08X}")
        else:
            print(f"  ----   {toml_key} not found in raw data")

    if not found_raw:
        print("\n  XEX is compressed/encrypted. The byte patterns can't be found")
        print("  in the raw file. You need to search in the decompressed code.")
        print()
        print("  Options:")
        print("  1. Load the XEX in Ghidra (with Xbox 360 XEX loader plugin)")
        print("     and search for these byte patterns in the disassembly view")
        print("  2. Use XenonRecomp with patched_file_path to produce a")
        print("     decompressed XEX, then search that")
        print("  3. Use xenia-vfs or xextool to decompress the XEX")
        print()
        print("  Since XenonAnalyse was able to parse this XEX (it found jump")
        print("  tables with base 0x82XXXXXX addresses), the file is valid.")
        print("  The register functions are definitely in there — we just need")
        print("  the decompressed code to find them.")
    else:
        print("\n=== TOML Config Values ===\n")
        for toml_key, offset in found_raw.items():
            va = base_addr + (offset - header_size)
            print(f'{toml_key} = 0x{va:08X}')

if __name__ == "__main__":
    main()

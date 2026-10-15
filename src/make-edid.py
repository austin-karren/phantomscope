#!/usr/bin/env python3
"""Synthesise a 128-byte EDID 1.3 block for a fake 4K display.

Two detailed timings: 3840x2160@60 (CVT-RB) as preferred, 1920x1080@60 (CEA)
as a fallback. No CEA extension block -- the sink is never real, so there is
no audio to describe and a single block keeps the driver's parsing trivial.
"""
import struct, sys

def dtd(pclk_khz, ha, hfp, hsw, hbp, va, vfp, vsw, vbp, hmm, vmm):
    hbl, vbl = hfp + hsw + hbp, vfp + vsw + vbp
    px = pclk_khz // 10                      # EDID stores 10 kHz units
    assert px <= 0xFFFF, "pixel clock out of range for EDID 1.3"
    return bytes([
        px & 0xFF, px >> 8,
        ha & 0xFF, hbl & 0xFF, ((ha >> 8) << 4) | (hbl >> 8),
        va & 0xFF, vbl & 0xFF, ((va >> 8) << 4) | (vbl >> 8),
        hfp & 0xFF, hsw & 0xFF, ((vfp & 0xF) << 4) | (vsw & 0xF),
        ((hfp >> 8) << 6) | ((hsw >> 8) << 4) | ((vfp >> 4) << 2) | (vsw >> 4),
        hmm & 0xFF, vmm & 0xFF, ((hmm >> 8) << 4) | (vmm >> 8),
        0, 0,
        0x1E,                                # digital separate, +hsync, +vsync
    ])

def descriptor(tag, payload):
    body = payload + b'\x0a' + b'\x20' * (13 - len(payload) - 1)
    return bytes([0, 0, 0, tag, 0]) + body

def mfg(code):
    v = 0
    for c in code:
        v = (v << 5) | (ord(c) - ord('A') + 1)
    return struct.pack('>H', v)

HMM, VMM = 1430, 800                          # ~65" 16:9, keeps DPI sane

e  = b'\x00' + b'\xff' * 6 + b'\x00'          # header
e += mfg('LNX')                               # manufacturer
e += struct.pack('<H', 0x2160)                # product code
e += struct.pack('<I', 0x00000001)            # serial
e += bytes([1, 36])                           # week 1, year 2026
e += bytes([1, 3])                            # EDID 1.3
e += bytes([0x80, HMM // 10, VMM // 10, 0x78, 0x06])  # digital, size cm, gamma 2.2, sRGB+preferred
e += bytes([0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54])  # sRGB chromaticity
e += bytes([0x00, 0x00, 0x00])                # no established timings
e += bytes([0x01, 0x01] * 8)                  # no standard timings

e += dtd(533280, 3840, 48, 32, 80, 2160, 3, 5, 54, HMM, VMM)   # 3840x2160@60 CVT-RB
e += dtd(148500, 1920, 88, 44, 148, 1080, 4, 5, 36, HMM, VMM)  # 1920x1080@60
e += descriptor(0xFD, bytes([50, 61, 30, 150, 60, 0x00]))      # range limits, 600 MHz cap
e += descriptor(0xFC, b'Virtual 4K')                           # monitor name

e += bytes([0x00])                            # no extension blocks
assert len(e) == 127, len(e)
e = e[:127] + bytes([(-sum(e[:127])) & 0xFF]) # checksum

sys.stdout.buffer.write(e)

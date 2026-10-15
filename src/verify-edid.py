import sys
e = open(sys.argv[1], 'rb').read()
assert e[:8] == b'\x00' + b'\xff'*6 + b'\x00', 'bad header'
assert len(e) == 128, 'bad length'
assert sum(e) % 256 == 0, 'bad checksum'
v = (e[8] << 8) | e[9]
mfg = ''.join(chr(((v >> s) & 0x1f) + 64) for s in (10, 5, 0))
print(f'mfg={mfg} edid={e[18]}.{e[19]} ext={e[126]} checksum=ok '
      f'size={e[21]}x{e[22]}cm')
for i in range(54, 126, 18):
    d = e[i:i+18]
    if d[0] == 0 and d[1] == 0:
        tag = d[3]
        txt = d[5:].split(b'\x0a')[0].decode('ascii', 'replace')
        print(f'  descriptor tag=0x{tag:02x} {txt if tag==0xfc else list(d[5:11])}')
        continue
    pclk = ((d[1] << 8) | d[0]) * 10000
    ha = ((d[4] >> 4) << 8) | d[2]; hbl = ((d[4] & 0xf) << 8) | d[3]
    va = ((d[7] >> 4) << 8) | d[5]; vbl = ((d[7] & 0xf) << 8) | d[6]
    hfp = ((d[11] >> 6) << 8) | d[8]; hsw = (((d[11] >> 4) & 3) << 8) | d[9]
    vfp = (((d[11] >> 2) & 3) << 4) | (d[10] >> 4)
    vsw = ((d[11] & 3) << 4) | (d[10] & 0xf)
    hz = pclk / ((ha + hbl) * (va + vbl))
    print(f'  DTD {ha}x{va}@{hz:.3f}Hz  pclk={pclk/1e6:.2f}MHz  '
          f'total={ha+hbl}x{va+vbl}  hsync({hfp},{hsw}) vsync({vfp},{vsw})')

# HuC6230 ADPCM decoder

# Input formats:
# - "bin": 16-bit (as read from KRAM), big-endian
# - "wav": 8-bit (as read from CD-ROM)
# Output format: 16-bit signed PCM, big-endian

import sys

# Ratio between output and input sample rates (1, 2, 4, 8)
sr = 1

ltab = [-1, -1, -1, -1, 2, 4, 6, 8]

stab = [
    16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66,
    73, 80, 88, 97, 107, 118, 130, 143,
    157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658,
    724, 796, 876, 963, 1060, 1166, 1282, 1411,
    1552
]

sl = 0
ss = stab[sl]
p = 0x20000
tim = 0


def decode(a, fout):
    dt = adpcm_in(a)

    for _ in range(sr):
        pcm_out(dt, fout)


def adpcm_in(a):
    global sl, ss

    c = a >> 3  # code: step sign
    d = a & 7   # data: step magnitude

    dt = ((d + 1) * (8 // sr)) * ss
    dt = -dt if c else dt

    sl = sl + ltab[d]
    sl = max(min(sl, 48), 0)
    ss = stab[sl]

    global tim
    tim += 1
    if sl == 48:
        print("max", tim / 15735)

    return dt


def pcm_out(dt, fout):
    global p

    p = p + dt
    p = max(min(p, 0x3ffff), 0)
    so = ((p >> 2) - 0x8000) & 0xffff
    fout.write(bytes([so >> 8, so & 0xff]))


def main():
    global sr

    fnin = sys.argv[1] if len(sys.argv) > 1 else "-"
    fnout = sys.argv[2] if len(sys.argv) > 2 else "-"
    sr = int(sys.argv[3]) if len(sys.argv) > 3 else 1

    fin = open(fnin, "rb") if fnin != "-" else sys.stdin.buffer
    fout = open(fnout, "wb") if fnout != "-" else sys.stdout.buffer

    fmt = fnin[-3:]
    if fmt == 'wav':
        fin.read(42)

    while True:
        if fmt == 'bin':
            w = fin.read(2)
            if len(w) < 2:
                break
            decode((w[1] >> 0) & 0xf, fout)
            decode((w[1] >> 4) & 0xf, fout)
            decode((w[0] >> 0) & 0xf, fout)
            decode((w[0] >> 4) & 0xf, fout)
        elif fmt == 'wav':
            w = fin.read(1)
            if len(w) < 1:
                break
            decode((w[0] >> 0) & 0xf, fout)
            decode((w[0] >> 4) & 0xf, fout)

if __name__ == '__main__':
    main()

# HuC6230 ADPCM decoder

# Input format: 16-bit (as read from KRAM), big-endian
# Output format: 16-bit signed PCM, big-endian

import sys

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

p = 0x20000
sl = 0
ss = stab[sl]

def decode(a, fout):
    global p, sl, ss

    c = a >> 3  # code: step sign
    d = a & 7   # data: step magnitude

    dt = ((d + 1) * 8) * ss
    dt = -dt if c else dt
    p = p + dt
    p = max(min(p, 0x3ffff), 0)

    so = ((p >> 2) - 0x8000) & 0xffff
    fout.write(bytes([so >> 8, so & 0xff]))

    sl = sl + ltab[d]
    sl = max(min(sl, 48), 0)
    ss = stab[sl]

def main():
    fin = open(sys.argv[1], "rb")
    fout = open(sys.argv[2], "wb")

    while True:
        w = fin.read(2)
        if len(w) < 2:
            break
        decode((w[1] >> 0) & 0xf, fout)
        decode((w[1] >> 4) & 0xf, fout)
        decode((w[0] >> 0) & 0xf, fout)
        decode((w[0] >> 4) & 0xf, fout)

if __name__ == '__main__':
    main()

import sys


def main():
    fnin = sys.argv[1]
    fnout = fnin[:-4] + '.hex'
    fin = open(fnin, "rb")
    fout = open(fnout, "w")

    while True:
        b = fin.read(2)
        if not len(b):
            break
        w = b[0] | (b[1] << 8)
        print(f'{w:04x}', file=fout)

    fin.close()
    fout.close()


if __name__ == '__main__':
    main()

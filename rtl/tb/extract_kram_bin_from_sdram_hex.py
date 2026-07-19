def do_page(page):
    fout = open(f"kram{page}.bin", "wb")

    for k in range(2):
        fin = open("sdram.hex", "r")

        start = 0x1000000 * (k + 1) + 0x40000 * page
        for i in range(start // 2):
            fin.readline()
    
        for i in range(0x40000 // 2):
            w = int(fin.readline(), 16)
            fout.write(bytes([w & 0xff, w >> 8]))
            if i % 0x200 == 0x1ff:
                for j in range(0x200):
                    fin.readline()

        fin.close()

    fout.close()


def main():
    do_page(0)
    do_page(1)


if __name__ == '__main__':
    main()

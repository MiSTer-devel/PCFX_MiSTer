def main():
    fin = open("sdram.hex", "r")
    fout = open("sdram.bin", "wb")

    for i in range(0x2000000 // 2):
        w = int(fin.readline(), 16)
        fout.write(bytes([w & 0xff, w >> 8]))
        if i % 0x200 == 0x1ff:
            for j in range(0x200):
                fin.readline()

    fin.close()
    fout.close()


if __name__ == '__main__':
    main()

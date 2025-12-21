all: memtest.bin

%.acf: %.S
	~/src/asl/obj/asl $^ -o $@ -L

%.bin: %.acf
	p2bin $^ $@ -r 0xfff00000-0xffffffff

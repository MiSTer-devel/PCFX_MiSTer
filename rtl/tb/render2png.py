import sys
import re
from PIL import Image, ImageColor, ImageDraw

img = Image.new('RGB', (320, 242))
d = ImageDraw.Draw(img)

with open(sys.argv[1], "r") as fin:
    y = 0
    for line in fin.readlines():
        for x in range(len(line)//6):
            w = line[x*6:x*6+6]
            if not re.match(r'[0-9a-fA-F]{6}', w):
                continue
            r = int(w[0:2], 16)
            g = int(w[2:4], 16)
            b = int(w[4:6], 16)
            c = (r,g,b)
            d.point((x, y), fill=c)
        y = y + 1

img.save(sys.argv[2])

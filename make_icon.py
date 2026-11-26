import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024 * 2  # supersampling
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Squircle (grille macOS : 824/1024 de contenu, centré)
inset = int(100 / 1024 * S)
size = S - 2 * inset
radius = int(185 / 1024 * S)

# dégradé ambre
grad = Image.new("RGBA", (size, size))
gd = ImageDraw.Draw(grad)
top, bottom = (255, 196, 61), (240, 128, 20)
for y in range(size):
    t = y / (size - 1)
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
    gd.line([(0, y), (size, y)], fill=c)
mask = Image.new("L", (size, size), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)

# ombre portée
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sh = Image.new("L", (S, S), 0)
ImageDraw.Draw(sh).rounded_rectangle([inset, inset + 24, inset + size, inset + size + 24], radius=radius, fill=110)
sh = sh.filter(ImageFilter.GaussianBlur(40))
shadow.putalpha(sh)
img = Image.alpha_composite(img, shadow)
img.paste(grad, (inset, inset), mask)

# alvéoles hexagonales blanches (7 : une centrale + 6 autour)
d = ImageDraw.Draw(img)
cx, cy = S / 2, S / 2
r = size * 0.118          # rayon d'un hexagone
gap = r * 0.16
step = (r * math.sqrt(3)) + gap   # distance entre centres

def hexagon(x, y, rr):
    return [(x + rr * math.cos(math.radians(60 * k + 30)), y + rr * math.sin(math.radians(60 * k + 30))) for k in range(6)]

centers = [(cx, cy)] + [(cx + step * math.cos(math.radians(60 * k)), cy + step * math.sin(math.radians(60 * k))) for k in range(6)]
for i, (x, y) in enumerate(centers):
    fill = (255, 255, 255, 255) if i == 0 else (255, 255, 255, 215)
    d.polygon(hexagon(x, y, r), fill=fill)

# point "notification" dans l'alvéole centrale
d.ellipse([cx - r * 0.32, cy - r * 0.32, cx + r * 0.32, cy + r * 0.32], fill=(240, 128, 20, 255))

img = img.resize((1024, 1024), Image.LANCZOS)
img.save("icon_1024.png")
img.save("AppIcon.icns", sizes=[(16,16),(32,32),(64,64),(128,128),(256,256),(512,512),(1024,1024)])

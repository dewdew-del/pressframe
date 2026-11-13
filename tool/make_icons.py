"""Draws the PressFrame logo (folded newspaper, the photo carries the band) and writes every icon the builds need.
Run from the repo root: python tool/make_icons.py"""
from PIL import Image, ImageDraw

S = 2048  # drawn large, then scaled down for smooth edges
u = S / 200  # the design is on a 200 x 200 grid


def box(x0, y0, x1, y1):
    return [x0 * u, y0 * u, x1 * u, y1 * u]


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle(box(0, 0, 200, 200), radius=44 * u, fill="#1e1e1e")
GRAY = "#9a9a9a"
d.rounded_rectangle(box(120, 66, 160, 158), radius=12 * u, fill=GRAY)  # back page
d.rounded_rectangle(box(48, 42, 138, 158), radius=10 * u, fill="#ffffff")  # front page
d.rounded_rectangle(box(60, 54, 126, 64), radius=3 * u, fill="#1e1e1e")  # masthead
d.rounded_rectangle(box(60, 74, 126, 118), radius=4 * u, fill="#1e1e1e")  # photo
d.rounded_rectangle(box(60, 104, 126, 118), radius=4 * u, fill="#4da3ff")  # band on the photo
d.rectangle(box(60, 104, 126, 110), fill="#4da3ff")  # square off the band's top corners
d.rounded_rectangle(box(60, 128, 126, 134), radius=3 * u, fill=GRAY)  # text lines
d.rounded_rectangle(box(60, 140, 104, 146), radius=3 * u, fill=GRAY)


def at(size):
    return img.resize((size, size), Image.LANCZOS)


for name, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    at(size).save(f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")
at(256).save(
    "windows/runner/resources/app_icon.ico",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
at(96).save("assets/logo.png")  # shown in the app's top bar
at(512).save("docs/logo.png")

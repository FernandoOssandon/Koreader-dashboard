"""Genera los 13 iconos del clima (96 y 48 px) como PNG en escala de grises con alpha.

Dibujados aquí mismo, sin recursos externos: no hay licencias que respetar.
Estilo pensado para E-Ink: trazo negro grueso y rellenos blancos, sin grises de fondo.

Uso:  pip install pillow && python make_icons.py
Salida: ../dashboardscreensaver.koplugin/icons/<icono>_96.png y <icono>_48.png
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "dashboardscreensaver.koplugin" / "icons"
S = 768  # lienzo de trabajo (8x el tamaño mayor) para suavizar los bordes al reducir
INK, PAPER, CLEAR = (0, 0, 0, 255), (255, 255, 255, 255), (0, 0, 0, 0)
T = 34  # grosor del trazo


def canvas():
    im = Image.new("RGBA", (S, S), CLEAR)
    return im, ImageDraw.Draw(im)


def disc(d, cx, cy, r, fill):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def sun(d, cx, cy, r):
    for i in range(8):
        a = math.radians(i * 45)
        d.line([cx + math.cos(a) * (r + 40), cy + math.sin(a) * (r + 40),
                cx + math.cos(a) * (r + 105), cy + math.sin(a) * (r + 105)], fill=INK, width=T)
    disc(d, cx, cy, r + T // 2, INK)
    disc(d, cx, cy, r - T // 2, PAPER)


def moon(d, cx, cy, r):
    disc(d, cx, cy, r, INK)
    disc(d, cx + r * 0.55, cy - r * 0.35, r * 0.85, CLEAR)  # recorte que deja la media luna


def cloud_shapes(x, y, w):
    """Círculos + base de una nube con esquina superior izquierda (x, y) y ancho w."""
    h = w * 0.55
    return [("c", x + w * 0.30, y + h * 0.55, h * 0.36), ("c", x + w * 0.52, y + h * 0.36, h * 0.42),
            ("c", x + w * 0.74, y + h * 0.58, h * 0.32), ("r", x + w * 0.10, y + h * 0.55, x + w * 0.90, y + h * 0.95)]


def cloud(d, x, y, w):
    shapes = cloud_shapes(x, y, w)
    for fill, grow in ((INK, T // 2), (PAPER, -T // 2)):
        for kind, *p in shapes:
            if kind == "c":
                disc(d, p[0], p[1], p[2] + grow, fill)
            else:
                d.rounded_rectangle([p[0] - grow, p[1] - grow, p[2] + grow, p[3] + grow],
                                    radius=max(1, (p[3] - p[1]) / 2 + grow), fill=fill)
    return y + w * 0.55 * 0.95  # y del borde inferior


def drops(d, bottom, x0, x1, n, length=95, width=T, slant=30):
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        d.line([x + slant, bottom + 40, x - slant / 2, bottom + 40 + length], fill=INK, width=width)


def icon_clear_day():
    im, d = canvas(); sun(d, S / 2, S / 2, 150); return im


def icon_clear_night():
    im, d = canvas(); moon(d, S / 2 - 20, S / 2, 250); return im


def icon_partly_cloudy_day():
    im, d = canvas(); sun(d, 470, 260, 105); cloud(d, 60, 330, 560); return im


def icon_partly_cloudy_night():
    im, d = canvas(); moon(d, 470, 260, 165); cloud(d, 60, 330, 560); return im


def icon_cloudy():
    im, d = canvas(); cloud(d, 250, 130, 460); cloud(d, 40, 290, 560); return im


def icon_fog():
    im, d = canvas()
    for i, (x0, x1) in enumerate([(120, 620), (170, 660), (100, 560), (200, 640)]):
        y = 210 + i * 120
        d.rounded_rectangle([x0, y, x1, y + T], radius=T / 2, fill=INK)
    return im


def icon_drizzle():
    im, d = canvas(); b = cloud(d, 90, 150, 560)
    for i in range(3):
        for j in range(2):
            disc(d, 230 + i * 150 + j * 70, b + 90 + j * 105, 20, INK)
    return im


def icon_rain():
    im, d = canvas(); b = cloud(d, 90, 150, 560); drops(d, b, 200, 600, 4); return im


def icon_heavy_rain():
    im, d = canvas(); b = cloud(d, 90, 110, 560); drops(d, b, 180, 620, 5, length=150, width=T + 8); return im


def icon_showers():
    im, d = canvas(); sun(d, 520, 210, 85); b = cloud(d, 70, 250, 540); drops(d, b, 180, 520, 3); return im


def icon_snow():
    im, d = canvas(); b = cloud(d, 90, 150, 560)
    for cx, cy in [(220, b + 95), (380, b + 95), (540, b + 95), (300, b + 200), (460, b + 200)]:
        for a in (0, 60, 120):
            r = math.radians(a)
            d.line([cx - math.cos(r) * 42, cy - math.sin(r) * 42, cx + math.cos(r) * 42, cy + math.sin(r) * 42],
                   fill=INK, width=T // 2 + 4)
    return im


def icon_thunderstorm():
    im, d = canvas(); b = cloud(d, 90, 110, 560)
    bolt = [(400, b - 10), (290, b + 130), (370, b + 130), (320, b + 270), (500, b + 90), (410, b + 90), (470, b - 10)]
    d.polygon(bolt, fill=INK)
    return im


def icon_unknown():
    im, d = canvas()
    d.arc([230, 140, 540, 420], start=200, end=90 + 360, fill=INK, width=T + 10)
    d.line([385, 420, 385, 500], fill=INK, width=T + 10)
    disc(d, 385, 615, 30, INK)
    return im


ICONS = {
    "clear_day": icon_clear_day, "clear_night": icon_clear_night,
    "partly_cloudy_day": icon_partly_cloudy_day, "partly_cloudy_night": icon_partly_cloudy_night,
    "cloudy": icon_cloudy, "fog": icon_fog, "drizzle": icon_drizzle, "rain": icon_rain,
    "heavy_rain": icon_heavy_rain, "snow": icon_snow, "showers": icon_showers,
    "thunderstorm": icon_thunderstorm, "unknown": icon_unknown,
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, draw in ICONS.items():
        big = draw()
        for size in (96, 48):
            big.resize((size, size), Image.LANCZOS).convert("LA").save(OUT / f"{name}_{size}.png", optimize=True)
    print(f"{len(ICONS) * 2} iconos en {OUT}")


if __name__ == "__main__":
    main()

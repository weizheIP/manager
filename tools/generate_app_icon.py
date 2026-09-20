#!/usr/bin/env python3
"""Generate the three 1024px iOS App Icon appearances for 次第."""

from pathlib import Path

from PIL import Image, ImageDraw


SIZE = 1024
SCALE = 4
OUTPUT = Path(__file__).resolve().parents[1] / "manager/Assets.xcassets/AppIcon.appiconset"


def gradient(top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (SIZE * SCALE, SIZE * SCALE))
    draw = ImageDraw.Draw(image)
    height = SIZE * SCALE
    for y in range(height):
        ratio = y / (height - 1)
        color = tuple(round(a + (b - a) * ratio) for a, b in zip(top, bottom))
        draw.line((0, y, height, y), fill=color)
    return image


def draw_icon(filename: str, top: tuple[int, int, int], bottom: tuple[int, int, int],
              ridge: tuple[int, int, int], step: tuple[int, int, int], sun: tuple[int, int, int]) -> None:
    image = gradient(top, bottom)
    draw = ImageDraw.Draw(image)
    s = SCALE

    # Quiet mountain silhouettes connect the icon to the app's daily-reading card.
    draw.polygon([(0, 760*s), (225*s, 610*s), (405*s, 735*s), (650*s, 530*s),
                  (1024*s, 775*s), (1024*s, 1024*s), (0, 1024*s)], fill=ridge)
    draw.ellipse((708*s, 170*s, 842*s, 304*s), fill=sun)

    # Four ascending stones express “次第”: progress in a clear, calm order.
    stones = [
        (190, 700, 430, 802),
        (310, 565, 550, 667),
        (430, 430, 670, 532),
        (550, 295, 790, 397),
    ]
    for left, top_y, right, bottom_y in stones:
        draw.rounded_rectangle((left*s, top_y*s, right*s, bottom_y*s), radius=48*s, fill=step)

    image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(OUTPUT / filename, optimize=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    draw_icon("AppIcon.png", (91, 74, 108), (132, 116, 146),
              (77, 62, 92), (247, 241, 229), (207, 190, 218))
    draw_icon("AppIcon-dark.png", (24, 20, 30), (51, 42, 60),
              (32, 27, 39), (212, 196, 225), (115, 92, 134))
    draw_icon("AppIcon-tinted.png", (27, 27, 27), (70, 70, 70),
              (40, 40, 40), (244, 244, 244), (155, 155, 155))


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


def remove_connected_white_background(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def is_background(x: int, y: int) -> bool:
        red, green, blue, _alpha = pixels[x, y]
        return min(red, green, blue) >= 238 and max(red, green, blue) - min(red, green, blue) <= 14

    def enqueue(x: int, y: int) -> None:
        index = y * width + x
        if visited[index] or not is_background(x, y):
            return
        visited[index] = 1
        queue.append((x, y))

    for x in range(width):
        enqueue(x, 0)
        enqueue(x, height - 1)
    for y in range(height):
        enqueue(0, y)
        enqueue(width - 1, y)

    while queue:
        x, y = queue.popleft()
        red, green, blue, _alpha = pixels[x, y]
        whiteness = min(red, green, blue)
        alpha = max(0, min(255, (246 - whiteness) * 32))
        pixels[x, y] = (red, green, blue, alpha)
        if x > 0:
            enqueue(x - 1, y)
        if x + 1 < width:
            enqueue(x + 1, y)
        if y > 0:
            enqueue(x, y - 1)
        if y + 1 < height:
            enqueue(x, y + 1)

    return rgba


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate ScreenPlayer PNG and Windows ICO assets.")
    parser.add_argument("source", type=Path)
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()

    args.output_directory.mkdir(parents=True, exist_ok=True)
    icon = remove_connected_white_background(Image.open(args.source))
    icon.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
    icon.save(args.output_directory / "app_icon.png", optimize=True)

    splash_icon = icon.resize((256, 256), Image.Resampling.LANCZOS)
    splash_icon.save(args.output_directory / "app_icon_256.png", optimize=True)

    icon.save(
        args.output_directory / "app_icon.ico",
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Remove white background from an image and make it transparent."""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow not installed. Run: pip install Pillow")
    sys.exit(1)


def remove_white_background(input_path: str, output_path: str | None = None, tolerance: int = 20):
    """
    Remove white/near-white background from an image.
    
    Args:
        input_path: Path to input image
        output_path: Path for output (defaults to input with _transparent suffix)
        tolerance: How close to white a pixel must be (0-255, higher = more aggressive)
    """
    input_file = Path(input_path)
    
    if output_path is None:
        output_path = input_file.parent / f"{input_file.stem}_transparent.png"
    
    # Open and convert to RGBA
    img = Image.open(input_file).convert("RGBA")
    data = img.getdata()
    
    new_data = []
    removed_count = 0
    
    for pixel in data:
        r, g, b, a = pixel
        
        # Check if pixel is white or near-white
        # All channels must be above (255 - tolerance)
        threshold = 255 - tolerance
        if r > threshold and g > threshold and b > threshold:
            # Make transparent
            new_data.append((r, g, b, 0))
            removed_count += 1
        else:
            new_data.append(pixel)
    
    img.putdata(new_data)
    img.save(output_path, "PNG")
    
    total = len(data)
    percent = (removed_count / total) * 100
    print(f"✓ Removed {removed_count:,} white pixels ({percent:.1f}%)")
    print(f"✓ Saved to: {output_path}")


def main():
    if len(sys.argv) < 2:
        print("Usage: remove-bg.py <input_image> [output_image] [tolerance]")
        print("")
        print("Arguments:")
        print("  input_image   Path to image with white background")
        print("  output_image  Output path (optional, defaults to input_transparent.png)")
        print("  tolerance     How aggressive to remove white (0-255, default: 20)")
        print("")
        print("Example:")
        print("  ./scripts/remove-bg.py docs/github-app-logo.png")
        print("  ./scripts/remove-bg.py logo.png logo_clean.png 30")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None
    tolerance = int(sys.argv[3]) if len(sys.argv) > 3 else 20
    
    if not Path(input_path).exists():
        print(f"Error: File not found: {input_path}")
        sys.exit(1)
    
    remove_white_background(input_path, output_path, tolerance)


if __name__ == "__main__":
    main()


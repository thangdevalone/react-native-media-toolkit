import os
import sys
import glob

# Try to import required libraries, prompt user if missing
try:
    from PIL import Image
    from pillow_lut import load_cube_file
except ImportError:
    print("Missing required libraries.")
    print("Please install them by running:")
    print("pip install Pillow pillow-lut")
    sys.exit(1)

def generate_hald_identity(level=8):
    """
    Generates an identity Hald CLUT image.
    Level 8 creates a 512x512 image (LUT size 64).
    """
    print(f"Generating identity Hald image of level {level}...")
    N = level ** 2
    size = level ** 3
    
    img = Image.new('RGB', (size, size))
    pixels = img.load()
    
    for y in range(size):
        for x in range(size):
            r_idx = x % N
            g_idx = y % N
            b_idx = (y // N) * level + (x // N)
            
            r = int(round((r_idx / (N - 1)) * 255.0))
            g = int(round((g_idx / (N - 1)) * 255.0))
            b = int(round((b_idx / (N - 1)) * 255.0))
            
            pixels[x, y] = (r, g, b)
            
    return img

def convert_cubes_to_halds(input_dir, output_dir, level=8):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    cube_files = glob.glob(os.path.join(input_dir, "*.cube"))
    
    if not cube_files:
        print(f"No .cube files found in {input_dir}")
        return

    # Generate the base Hald image once
    identity_hald = generate_hald_identity(level)
    
    for cube_path in cube_files:
        filename = os.path.basename(cube_path)
        name, _ = os.path.splitext(filename)
        output_path = os.path.join(output_dir, f"{name}.png")
        
        print(f"Converting {filename}...")
        try:
            # Load the LUT
            lut = load_cube_file(cube_path)
            
            # Apply the LUT to the identity Hald image
            hald_image = identity_hald.filter(lut)
            
            # Save the result
            hald_image.save(output_path)
            print(f"  -> Saved to {output_path}")
        except Exception as e:
            print(f"  -> Error converting {filename}: {e}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Convert .cube LUTs to HALD PNG images.")
    parser.add_argument("--input", "-i", type=str, default=".", help="Directory containing .cube files")
    parser.add_argument("--output", "-o", type=str, default="hald_output", help="Directory to save HALD .png files")
    parser.add_argument("--level", "-l", type=int, default=8, help="Hald level (default 8, creates 512x512 image)")
    
    args = parser.parse_args()
    convert_cubes_to_halds(args.input, args.output, args.level)
    print("Done!")

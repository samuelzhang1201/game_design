"""Tile the Blender-rendered canter frames; run with Python and Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw
base = Path(__file__).resolve().parents[3] / 'assets/3D/characters/king/model_wip'
files = [base / f'MARCH_{view}_{frame:03}.png'
         for view in ('side', 'front') for frame in range(0, 16, 2)]
sheet = Image.new('RGB', (1920, 520), (35, 35, 35))
draw = ImageDraw.Draw(sheet)
for index, path in enumerate(files):
    frame = Image.open(path).convert('RGB').resize((240, 240))
    x, y = index % 8 * 240, index // 8 * 260
    sheet.paste(frame, (x, y))
    draw.text((x + 5, y + 241), path.stem, fill='white')
sheet.save(base / 'MARCH_contact_sheet.jpg')
frames = [Image.open(path).convert('RGB').resize((400, 400)) for path in files[:8]]
frames[0].save(base / 'MARCH.gif', save_all=True, append_images=frames[1:], duration=67, loop=0)
assert (base / 'MARCH_contact_sheet.jpg').stat().st_size > 0
assert (base / 'MARCH.gif').stat().st_size > 0

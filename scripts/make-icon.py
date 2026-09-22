#!/usr/bin/env python3
"""生成 UGOS 应用图标:上游 logo.svg → 256x256 圆角卡片 PNG (<100KB)。

按 build-and-release.md 记录的坑操作:
- SVG 内联进 HTML(不用 <img src=file://>,同源策略会让截图挂死)
- 不加 --virtual-time-budget
- 不等 Chrome 自己退出:轮询 PNG 大小稳定后自己 kill
- 圆角透明自己用 PIL 画 mask(--default-background-color 实测不生效)
"""
import subprocess, time, os, sys, pathlib

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SVG = HERE / "logo.svg"
OUT = ROOT / "com.rachelos.wemprss" / "rootfs_common" / "icon.png"
SHOT = HERE / "icon-1024.png"

svg = SVG.read_text()

html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
* {{ margin:0; padding:0; }}
body {{ width:1024px; height:1024px; overflow:hidden; }}
.card {{
  width:1024px; height:1024px;
  background: linear-gradient(160deg, #ffffff 0%, #fdf2f2 55%, #fde8e8 100%);
  display:flex; align-items:center; justify-content:center;
}}
svg {{ width:640px; height:640px; }}
</style></head>
<body><div class="card">{svg}</div></body></html>"""

html_path = HERE / "icon.html"
html_path.write_text(html)

if SHOT.exists():
    SHOT.unlink()

proc = subprocess.Popen([
    CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
    "--force-device-scale-factor=1",
    "--window-size=1024,1024",
    f"--screenshot={SHOT}",
    html_path.as_uri(),
], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# 轮询 PNG 大小稳定即认为写完(Chrome 写完不会自己退出)
last, stable = -1, 0
for _ in range(150):
    time.sleep(0.2)
    if SHOT.exists():
        size = SHOT.stat().st_size
        if size == last and size > 0:
            stable += 1
            if stable >= 5:
                break
        else:
            stable = 0
        last = size
proc.kill()
proc.wait()

if not SHOT.exists() or SHOT.stat().st_size == 0:
    print("screenshot failed"); sys.exit(1)

# ---- PIL: 降采样 + 圆角 alpha mask ----
from PIL import Image, ImageDraw

img = Image.open(SHOT).convert("RGB")
img = img.resize((256, 256), Image.LANCZOS)

mask = Image.new("L", (256, 256), 0)
d = ImageDraw.Draw(mask)
d.rounded_rectangle([0, 0, 255, 255], radius=56, fill=255)

out = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
out.paste(img, (0, 0), mask)
OUT.parent.mkdir(parents=True, exist_ok=True)
out.save(OUT, "PNG", optimize=True)

# 自检: 四角透明 / 边中点实心 / 体积
px = out.load()
corners = [px[0,0], px[255,0], px[0,255], px[255,255]]
assert all(c[3] == 0 for c in corners), f"四角未透明: {corners}"
assert px[128,0][3] == 255 and px[128,255][3] == 255, "边中点应实心"
size = OUT.stat().st_size
assert size < 100 * 1024, f"icon 超过 100KB: {size}"
print(f"icon ok: {OUT} ({size} bytes)")

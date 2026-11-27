"""
把 3 张"正俯视"高清币面九宫格切成 3D 币面贴图（assets/image/coins/coin_*.png）。

与 slice_sheets.py 的区别：
  - 币面贴在 3D 圆柱顶上，要求严格正圆：这里按检测到的圆心/半径做抗锯齿圆形遮罩，
    背景是什么纯色都无所谓，也不会留白边。
  - 输出 512x512（2 的幂，移动端才能正常生成 mipmap），圆直径占画布 96%，
    与旧贴图一致，Machine3D / Art.DrawCoin 的缩放不用改。

用法：
  python devtools/slice_coins_hd.py                 # 切图并覆盖 assets/image/coins/
  python devtools/slice_coins_hd.py --qa qa.png     # 额外输出深色底 QA 总览
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "devtools" / "raw_sheets"
OUT_DIR = ROOT / "assets" / "image" / "coins"

OUT_SIZE = 512
FILL = 0.96          # 圆直径占输出画布的比例
EDGE_TRIM = 0.015    # 半径内收比例，切掉边缘外发光/白边
SUPERSAMPLE = 4      # 遮罩超采样倍数（抗锯齿）
BG_TOL = 38          # 与背景色的差异阈值

# 每张图按行优先排列的 9 格；None 表示跳过该格
SHEETS: dict[str, tuple[str | None, ...]] = {
    "coins_hd_1.png": ("gold", "emerald", "split", "heavy", "thunder", "bomb", "spring", "magnet", "ruby"),
    "coins_hd_2.png": ("neon", "frost", "ghost", "jackpot7", "blackhole", "giant", "nuke", "mini", "slag"),
    # 第 3 行中/右是金币、银币的备选版，默认不用；想换就把 None 改成 "gold" / "mini" 并删掉第 1 张图里的对应项
    "coins_hd_3.png": ("vault", "midas", "thor", "supernova", "hydra", "singularity", "carnival", None, None),
}


def _bg_color(cell: Image.Image) -> tuple[int, int, int]:
    w, h = cell.size
    px = cell.load()
    pts = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3), (w // 2, 2), (w // 2, h - 3), (2, h // 2), (w - 3, h // 2)]
    cols = sorted(px[x, y][:3] for x, y in pts)
    return cols[len(cols) // 2]


def _longest_run(idx: list[int]) -> tuple[int, int]:
    best = (idx[0], idx[0] + 1)
    start = prev = idx[0]
    for v in idx[1:] + [None]:
        if v is None or v != prev + 1:
            if prev + 1 - start > best[1] - best[0]:
                best = (start, prev + 1)
            if v is None:
                break
            start = v
        prev = v
    return best


def _find_circle(cell: Image.Image) -> tuple[float, float, float]:
    """返回 (cx, cy, r)。用前景掩码每行/每列的像素数找出主圆的范围，忽略零星闪光点。"""
    bg = Image.new("RGB", cell.size, _bg_color(cell))
    diff = ImageChops.difference(cell.convert("RGB"), bg).convert("L")
    mask = diff.point(lambda v: 255 if v > BG_TOL else 0)
    w, h = mask.size
    data = mask.load()
    min_run = max(6, int(min(w, h) * 0.06))  # 一行/列至少这么多前景像素才算圆的一部分
    rows = [y for y in range(h) if sum(1 for x in range(w) if data[x, y]) >= min_run]
    cols = [x for x in range(w) if sum(1 for y in range(h) if data[x, y]) >= min_run]
    if not rows or not cols:
        raise ValueError("未检测到硬币")
    # 只取最长的连续区间：相邻格子的硬币可能探进本格边缘
    y0, y1 = _longest_run(rows)
    x0, x1 = _longest_run(cols)
    return (x0 + x1) / 2.0, (y0 + y1) / 2.0, max(x1 - x0, y1 - y0) / 2.0


def _cut_coin(sheet: Image.Image, cell_box: tuple[int, int, int, int]) -> Image.Image:
    # 在格子里找圆，再回到整张图上裁切（硬币可能贴着格子边缘）
    cx, cy, r = _find_circle(sheet.crop(cell_box))
    cx += cell_box[0]
    cy += cell_box[1]
    r_in = r * (1.0 - EDGE_TRIM)
    # 先按内收后的圆裁出正方形，再缩放到圆直径 = OUT_SIZE * FILL
    disc = int(round(OUT_SIZE * FILL))
    box = (cx - r_in, cy - r_in, cx + r_in, cy + r_in)
    face = sheet.convert("RGBA").resize((disc, disc), Image.LANCZOS, box=box)

    ss = disc * SUPERSAMPLE
    m = Image.new("L", (ss, ss), 0)
    ImageDraw.Draw(m).ellipse((0, 0, ss - 1, ss - 1), fill=255)
    m = m.resize((disc, disc), Image.LANCZOS)
    face.putalpha(m)

    out = Image.new("RGBA", (OUT_SIZE, OUT_SIZE), (0, 0, 0, 0))
    off = (OUT_SIZE - disc) // 2
    out.alpha_composite(face, (off, off))
    # 透明区域 RGB 用边缘色外扩，避免 mipmap/双线性采样时把黑/白底色混进边缘
    return _bleed_edges(out)


def _bleed_edges(img: Image.Image, passes: int = 24) -> Image.Image:
    rgb = img.convert("RGB")
    alpha = img.getchannel("A")
    solid = alpha.point(lambda v: 255 if v >= 128 else 0)
    filled = Image.new("RGB", img.size, (0, 0, 0))
    filled.paste(rgb, mask=solid)
    known = solid
    for _ in range(passes):
        grown = known.filter(_MAX3)
        new_px = ImageChops.subtract(grown, known)
        if not new_px.getbbox():
            break
        blurred = filled.filter(_BOX3)
        weight = known.filter(_BOX3)
        # 用邻域均值填充新像素（按已知像素权重归一化）
        bl = blurred.load()
        wl = weight.load()
        fl = filled.load()
        nl = new_px.load()
        w, h = img.size
        for y in range(h):
            for x in range(w):
                if nl[x, y]:
                    k = wl[x, y]
                    if k:
                        r, g, b = bl[x, y]
                        s = 255.0 / k
                        fl[x, y] = (min(255, int(r * s)), min(255, int(g * s)), min(255, int(b * s)))
        known = grown
    out = filled.convert("RGBA")
    out.putalpha(alpha)
    return out


_MAX3 = ImageFilter.MaxFilter(3)
_BOX3 = ImageFilter.BoxBlur(1)


def slice_all(raw_dir: Path, out_dir: Path) -> list[Path]:
    written: list[Path] = []
    for fname, ids in SHEETS.items():
        src = raw_dir / fname
        if not src.is_file():
            print(f"[skip] 缺少 {src}")
            continue
        img = Image.open(src).convert("RGB")
        w, h = img.size
        for idx, cid in enumerate(ids):
            if cid is None:
                continue
            c, r = idx % 3, idx // 3
            cell_box = (c * w // 3, r * h // 3, (c + 1) * w // 3, (r + 1) * h // 3)
            dest = out_dir / f"coin_{cid}.png"
            _cut_coin(img, cell_box).save(dest, format="PNG", optimize=True)
            written.append(dest)
            print(f"[ok] {dest.relative_to(ROOT)}")
    return written


def qa_sheet(paths: list[Path], dest: Path, tile: int = 160) -> None:
    cols = 7
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * tile, rows * tile), (18, 22, 44, 255))
    for i, p in enumerate(paths):
        im = Image.open(p).resize((tile - 8, tile - 8), Image.LANCZOS)
        sheet.alpha_composite(im, ((i % cols) * tile + 4, (i // cols) * tile + 4))
    sheet.save(dest)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw-dir", type=Path, default=RAW_DIR)
    ap.add_argument("--out-dir", type=Path, default=OUT_DIR)
    ap.add_argument("--qa", type=Path, default=None)
    args = ap.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    paths = slice_all(args.raw_dir, args.out_dir)
    if args.qa and paths:
        qa_sheet(paths, args.qa)
    print(f"共写出 {len(paths)} 张币面贴图")


if __name__ == "__main__":
    main()

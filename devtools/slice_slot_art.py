"""
切分九宫格老虎机 / JP CHANCE 抽奖格贴图（白底拼图 -> 透明 PNG）。

  devtools/raw_sheets/slot_symbols.png  3x3：金币 四叶草 闪电 / 红宝石 皇冠 星钻 / JP宝箱 格子底板 中心格底板
  devtools/raw_sheets/jp_tiles.png      2x2：MINI MAJOR / GRAND NEXT

输出到 assets/image/slot/ 与 assets/image/jp/，Skin.ProbeAutoAssets 会自动识别；
缺哪张就继续用程序化画法，不会报错。

用法：python devtools/slice_slot_art.py [--qa qa.png]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from slice_sheets import CellSpec, SheetSpec, _slice_one_sheet  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "devtools" / "raw_sheets"
OUT_ROOT = ROOT / "assets" / "image"

SHEETS = (
    SheetSpec(
        "slot_symbols.png", 3, 3,
        tuple(CellSpec(f"slot/sym_{i}.png", 256, 256, True, 0.03) for i in range(1, 8))
        + (
            CellSpec("slot/cell.png", 256, 256, True, 0.0, stretch_fill=True),
            CellSpec("slot/cell_center.png", 256, 256, True, 0.0, stretch_fill=True),
        ),
    ),
    SheetSpec(
        "jp_tiles.png", 2, 2,
        tuple(CellSpec(f"jp/tile_{k}.png", 256, 256, True, 0.0, stretch_fill=True)
              for k in ("mini", "major", "grand", "next")),
    ),
)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw-dir", type=Path, default=RAW_DIR)
    ap.add_argument("--qa", type=Path, default=None)
    args = ap.parse_args()
    written: list[Path] = []
    for sheet in SHEETS:
        src = args.raw_dir / sheet.filename
        if not src.is_file():
            print(f"[skip] 缺少 {src}")
            continue
        _slice_one_sheet(src, sheet, OUT_ROOT)
        written += [OUT_ROOT / c.rel_out for c in sheet.cells]
        print(f"[ok] {sheet.filename} -> {len(sheet.cells)} 张")
    if args.qa and written:
        tile = 160
        qa = Image.new("RGBA", (tile * 5, tile * ((len(written) + 4) // 5)), (18, 22, 44, 255))
        for i, p in enumerate(written):
            im = Image.open(p).convert("RGBA").resize((tile - 8, tile - 8), Image.LANCZOS)
            qa.alpha_composite(im, ((i % 5) * tile + 4, (i // 5) * tile + 4))
        qa.save(args.qa)


if __name__ == "__main__":
    main()

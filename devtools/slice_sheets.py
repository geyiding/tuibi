"""
自动切分 8 张拼图（7 张 3x3 九宫格 + 1 张 1x3 Boss 横拼）为游戏内全套 66+ 张独立 PNG 贴图（含 6 色按钮变体）。

用法：
  1. 将生成的拼图放入 devtools/raw_sheets/，文件名对齐：
     sheet_01_coins_a.png / sheet_02_coins_b.png / sheet_03_coins_evo.png
     sheet_04_relics_a.png / sheet_05_relics_b.png / sheet_06_ui_machine.png
     sheet_07_scenes_events.png / sheet_08_bosses.png
  2. 运行：python devtools/slice_sheets.py
  3. 导出暗夜底 QA 总览拼图：python devtools/slice_sheets.py --qa-sheet qa.png
  4. 仅验证脚本：python devtools/slice_sheets.py --self-test
"""

from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass
import math
from pathlib import Path
import shutil
import tempfile
from PIL import Image, ImageDraw, ImageFont


@dataclass(frozen=True)
class CellSpec:
    rel_out: str
    width: int
    height: int
    transparent: bool = True
    pad_ratio: float = 0.02
    stretch_fill: bool = False
    crop_y_bias: float = 0.5  # 0=靠顶裁, 0.5=居中, 1=靠底


@dataclass(frozen=True)
class SheetSpec:
    filename: str
    cols: int
    rows: int
    cells: tuple[CellSpec, ...]


SHEETS: tuple[SheetSpec, ...] = (
    SheetSpec(
        "sheet_01_coins_a.png",
        3,
        3,
        tuple(
            CellSpec(f"coins/coin_{cid}.png", 256, 256, True, 0.02)
            for cid in ("gold", "emerald", "split", "heavy", "thunder", "bomb", "spring", "magnet", "ruby")
        ),
    ),
    SheetSpec(
        "sheet_02_coins_b.png",
        3,
        3,
        tuple(
            CellSpec(f"coins/coin_{cid}.png", 256, 256, True, 0.02)
            for cid in ("neon", "frost", "ghost", "jackpot7", "blackhole", "giant", "nuke", "mini", "slag")
        ),
    ),
    SheetSpec(
        "sheet_03_coins_evo.png",
        3,
        3,
        tuple(
            [
                CellSpec(f"coins/coin_{cid}.png", 256, 256, True, 0.02)
                for cid in ("vault", "midas", "thor", "supernova", "hydra", "singularity", "carnival")
            ]
            + [
                CellSpec("relics/relic_first_surge.png", 192, 192, True, 0.03),
                CellSpec("relics/relic_prism.png", 192, 192, True, 0.03),
            ]
        ),
    ),
    SheetSpec(
        "sheet_04_relics_a.png",
        3,
        3,
        tuple(
            CellSpec(f"relics/relic_{rid}.png", 192, 192, True, 0.03)
            for rid in (
                "rail_guard",
                "turbo_pusher",
                "golden_pegs",
                "wide_gate",
                "metronome",
                "medkit",
                "big_pouch",
                "bankbook",
                "crit_seal",
            )
        ),
    ),
    SheetSpec(
        "sheet_05_relics_b.png",
        3,
        3,
        tuple(
            CellSpec(f"relics/relic_{rid}.png", 192, 192, True, 0.03)
            for rid in (
                "fever_amp",
                "double_barrel",
                "mag_lip",
                "powder_keg",
                "tesla_coil",
                "clover",
                "recycler",
                "vip_card",
                "overclock",
            )
        ),
    ),
    SheetSpec(
        "sheet_06_ui_machine.png",
        3,
        3,
        (
            CellSpec("ui/panel.png", 160, 120, True, 0.0, stretch_fill=True),
            CellSpec("ui/card.png", 140, 110, True, 0.0, stretch_fill=True),
            CellSpec("ui/slot.png", 64, 64, True, 0.0, stretch_fill=True),
            CellSpec("ui/button.png", 144, 48, True, 0.0, stretch_fill=True),
            CellSpec("ui/plate.png", 160, 44, True, 0.0, stretch_fill=True),
            CellSpec("ui/cloth.png", 160, 44, True, 0.0, stretch_fill=True),
            CellSpec("ui/banner.png", 180, 56, True, 0.0, stretch_fill=True),
            CellSpec("machine/pusher_bar.png", 320, 136, True, 0.01, stretch_fill=True),
            CellSpec("machine/gate_badge.png", 160, 128, True, 0.02, stretch_fill=False),
        ),
    ),
    SheetSpec(
        "sheet_07_scenes_events.png",
        3,
        3,
        (
            CellSpec("machine/backdrop_act1.png", 512, 480, False, 0.0, crop_y_bias=0.45),
            CellSpec("machine/backdrop_act2.png", 512, 480, False, 0.0, crop_y_bias=0.45),
            CellSpec("machine/backdrop_act3.png", 512, 480, False, 0.0, crop_y_bias=0.45),
            CellSpec("events/event_gold_altar.png", 400, 250, False, 0.0, crop_y_bias=0.38),
            CellSpec("events/event_scrap_smith.png", 400, 250, False, 0.0, crop_y_bias=0.22),
            CellSpec("events/event_lucky_wheel.png", 400, 250, False, 0.0, crop_y_bias=0.50),
            CellSpec("events/event_neon_spring.png", 400, 250, False, 0.0, crop_y_bias=0.42),
            CellSpec("events/event_magnet_trap.png", 400, 250, False, 0.0, crop_y_bias=0.46),
            CellSpec("events/event_vault_crack.png", 400, 250, False, 0.0, crop_y_bias=0.42),
        ),
    ),
    SheetSpec(
        "sheet_08_bosses.png",
        3,
        1,
        tuple(
            CellSpec(f"boss/boss_{bid}.png", 256, 256, True, 0.03)
            for bid in ("gatekeeper", "furnace", "vaultbeast")
        ),
    ),
)

REWORK_SHEET = SheetSpec(
    "sheet_09_rework.png",
    2,
    1,
    (
        CellSpec("relics/relic_golden_pegs.png", 192, 192, True, 0.03),
        CellSpec("ui/button.png", 144, 48, True, 0.0, stretch_fill=True),
    ),
)

# 对齐 Skin.lua VARIANTS 的 6 色按钮配色表（基于金橙立体底图做色相/明度重映射）
BUTTON_VARIANTS: dict[str, dict[str, object]] = {
    "primary": {"top": (255, 212, 66), "bot": (222, 132, 20), "edge": (138, 74, 10), "hi": 0.65},
    "cyan": {"top": (82, 236, 255), "bot": (22, 146, 214), "edge": (12, 72, 122), "hi": 0.42},
    "magenta": {"top": (255, 96, 190), "bot": (190, 34, 124), "edge": (98, 12, 64), "hi": 0.26},
    "green": {"top": (96, 240, 152), "bot": (32, 162, 88), "edge": (16, 86, 46), "hi": 0.42},
    "danger": {"top": (255, 104, 114), "bot": (188, 38, 52), "edge": (96, 14, 24), "hi": 0.26},
    "dark": {"top": (58, 72, 126), "bot": (28, 36, 72), "edge": (14, 18, 40), "hi": 0.16},
}


def _median_bg_rgb(rgba: Image.Image) -> tuple[int, int, int]:
    w, h = rgba.size
    samples: list[tuple[int, int, int]] = []
    px = rgba.load()
    pts = (
        (1, 1), (w // 2, 1), (w - 2, 1),
        (1, h // 2), (w - 2, h // 2),
        (1, h - 2), (w // 2, h - 2), (w - 2, h - 2),
    )
    for cx, cy in pts:
        r, g, b, _ = px[max(0, min(w - 1, cx)), max(0, min(h - 1, cy))]
        samples.append((r, g, b))
    rs = sorted(c[0] for c in samples)
    gs = sorted(c[1] for c in samples)
    bs = sorted(c[2] for c in samples)
    mid = len(samples) // 2
    return rs[mid], gs[mid], bs[mid]


def _key_border_background(rgba: Image.Image, tol: int = 44) -> Image.Image:
    """从四边向外连通 BFS 抠出纯白/近白背景（兼容 JPG 压缩噪点，双环柔化 + 反混色去白边）。"""
    w, h = rgba.size
    if w < 8 or h < 8:
        return rgba
    bg_r, bg_g, bg_b = _median_bg_rgb(rgba)
    raw = bytearray(rgba.tobytes())
    n = w * h
    bg_mask = bytearray(n)
    q: deque[int] = deque()
    tol_sq = tol * tol * 3
    near_white_bg = (bg_r > 220 and bg_g > 220 and bg_b > 220)

    def is_bg_idx(i: int) -> bool:
        off = i * 4
        if raw[off + 3] < 16:
            return True
        r, g, b = raw[off], raw[off + 1], raw[off + 2]
        dr = r - bg_r
        dg = g - bg_g
        db = b - bg_b
        if (dr * dr + dg * dg + db * db) <= tol_sq:
            return True
        # 容忍轻度 JPEG 灰白压缩涟漪（保证低饱和浅灰近白能贯通）
        if near_white_bg and r > 218 and g > 218 and b > 218 and (max(r, g, b) - min(r, g, b)) < 26:
            return True
        return False

    for x in range(w):
        for y in (0, h - 1):
            idx = y * w + x
            if not bg_mask[idx] and is_bg_idx(idx):
                bg_mask[idx] = 1
                q.append(idx)
    for y in range(1, h - 1):
        for x in (0, w - 1):
            idx = y * w + x
            if not bg_mask[idx] and is_bg_idx(idx):
                bg_mask[idx] = 1
                q.append(idx)

    while q:
        cur = q.popleft()
        x = cur % w
        y = cur // w
        if x > 0:
            ni = cur - 1
            if not bg_mask[ni] and is_bg_idx(ni):
                bg_mask[ni] = 1
                q.append(ni)
        if x + 1 < w:
            ni = cur + 1
            if not bg_mask[ni] and is_bg_idx(ni):
                bg_mask[ni] = 1
                q.append(ni)
        if y > 0:
            ni = cur - w
            if not bg_mask[ni] and is_bg_idx(ni):
                bg_mask[ni] = 1
                q.append(ni)
        if y + 1 < h:
            ni = cur + w
            if not bg_mask[ni] and is_bg_idx(ni):
                bg_mask[ni] = 1
                q.append(ni)

    # 识别紧邻背景的 1 环边缘并估算前景混合比例，做白底反混色（defringe）
    max_bg_dist = float(tol + 42)
    ring1 = bytearray(n)
    for i in range(n):
        if bg_mask[i]:
            continue
        x = i % w
        y = i // w
        if (
            (x > 0 and bg_mask[i - 1])
            or (x + 1 < w and bg_mask[i + 1])
            or (y > 0 and bg_mask[i - w])
            or (y + 1 < h and bg_mask[i + w])
        ):
            ring1[i] = 1

    for i in range(n):
        off = i * 4
        if bg_mask[i]:
            raw[off + 3] = 0
            continue
        if ring1[i]:
            r, g, b, a = raw[off], raw[off + 1], raw[off + 2], raw[off + 3]
            dist = math.sqrt(((r - bg_r) ** 2 + (g - bg_g) ** 2 + (b - bg_b) ** 2) / 3.0)
            if dist < max_bg_dist:
                t = max(0.18, min(1.0, (dist - tol * 0.45) / (max_bg_dist - tol * 0.45)))
                new_a = int(round(a * t))
                if new_a > 8:
                    # 消除混合白底色偏，让深色外框在深蓝背景上锐利不发白
                    inv = 1.0 / (new_a / 255.0)
                    raw[off] = max(0, min(255, int(round((r - (1.0 - t) * bg_r) * inv))))
                    raw[off + 1] = max(0, min(255, int(round((g - (1.0 - t) * bg_g) * inv))))
                    raw[off + 2] = max(0, min(255, int(round((b - (1.0 - t) * bg_b) * inv))))
                raw[off + 3] = new_a

    return Image.frombytes("RGBA", (w, h), bytes(raw))


def _fit_transparent_cell(cell_img: Image.Image, spec: CellSpec) -> Image.Image:
    w, h = cell_img.size
    trim_x = max(2, int(w * 0.02))
    trim_y = max(2, int(h * 0.02))
    cropped = cell_img.crop((trim_x, trim_y, max(trim_x + 4, w - trim_x), max(trim_y + 4, h - trim_y))).convert("RGBA")

    cw, ch = cropped.size
    if max(cw, ch) > 512:
        ratio = 512.0 / float(max(cw, ch))
        cropped = cropped.resize((max(16, int(round(cw * ratio))), max(16, int(round(ch * ratio)))), Image.Resampling.LANCZOS)

    keyed = _key_border_background(cropped)
    alpha_band = keyed.getchannel("A").point(lambda a: 255 if a > 24 else 0)
    bbox = alpha_band.getbbox()
    if bbox:
        keyed = keyed.crop(bbox)

    if spec.stretch_fill:
        # UI 九宫格框、推板等精确铺满目标尺寸，确保九宫格切片坐标精准落框
        return keyed.resize((spec.width, spec.height), Image.Resampling.LANCZOS)

    pad_w = max(0, int(round(spec.width * spec.pad_ratio)))
    pad_h = max(0, int(round(spec.height * spec.pad_ratio)))
    avail_w = max(4, spec.width - pad_w * 2)
    avail_h = max(4, spec.height - pad_h * 2)
    kw, kh = keyed.size
    scale = min(avail_w / max(1, kw), avail_h / max(1, kh))
    nw = max(1, int(round(kw * scale)))
    nh = max(1, int(round(kh * scale)))
    resized = keyed.resize((nw, nh), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (spec.width, spec.height), (0, 0, 0, 0))
    ox = (spec.width - nw) // 2
    oy = (spec.height - nh) // 2
    canvas.paste(resized, (ox, oy), resized)
    return canvas


def _fit_opaque_cell(cell_img: Image.Image, spec: CellSpec) -> Image.Image:
    w, h = cell_img.size
    trim_x = max(3, int(w * 0.035))
    trim_y = max(3, int(h * 0.035))
    cropped = cell_img.crop((trim_x, trim_y, max(trim_x + 4, w - trim_x), max(trim_y + 4, h - trim_y))).convert("RGB")
    cw, ch = cropped.size
    target_ar = spec.width / float(spec.height)
    cur_ar = cw / float(max(1, ch))
    if cur_ar > target_ar:
        new_w = max(4, int(round(ch * target_ar)))
        left = int(round((cw - new_w) * 0.5))
        cropped = cropped.crop((left, 0, left + new_w, ch))
    else:
        new_h = max(4, int(round(cw / target_ar)))
        top = int(round((ch - new_h) * spec.crop_y_bias))
        top = max(0, min(ch - new_h, top))
        cropped = cropped.crop((0, top, cw, top + new_h))
    return cropped.resize((spec.width, spec.height), Image.Resampling.LANCZOS)


def _generate_button_variants(base_btn_path: Path, ui_dir: Path) -> int:
    """由 sheet_06 切出的金色立体主按钮自动色调映射出 6 套主题按钮图（保留原有描边与高光）。"""
    if not base_btn_path.is_file():
        return 0
    base = Image.open(base_btn_path).convert("RGBA")
    w, h = base.size
    src_bytes = base.tobytes()
    generated = 0

    for name, pal in BUTTON_VARIANTS.items():
        if name == "primary":
            base.save(ui_dir / "button_primary.png", format="PNG")
            generated += 1
            continue

        out = bytearray(src_bytes)
        top_c, bot_c, edge_c = pal["top"], pal["bot"], pal["edge"]
        hi_mix = float(pal["hi"])
        for i in range(w * h):
            off = i * 4
            a = out[off + 3]
            if a < 10:
                continue
            r, g, b = out[off], out[off + 1], out[off + 2]
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0

            # 暗描边保持深色；非主按钮将强白光斑收敛为受控高光，保证白字高对比度
            if lum < 0.20:
                continue

            if lum < 0.42:
                # 底部厚立体阴影边
                t = max(0.0, min(1.0, (lum - 0.20) / 0.22))
                nr = int(edge_c[0] * (1 - t) + bot_c[0] * t)
                ng = int(edge_c[1] * (1 - t) + bot_c[1] * t)
                nb = int(edge_c[2] * (1 - t) + bot_c[2] * t)
            elif lum < 0.72:
                # 按钮主体渐变
                t = (lum - 0.42) / 0.30
                nr = int(bot_c[0] * (1 - t) + top_c[0] * t)
                ng = int(bot_c[1] * (1 - t) + top_c[1] * t)
                nb = int(bot_c[2] * (1 - t) + top_c[2] * t)
            else:
                # 顶部受光高亮缘（按变体明暗控白度）
                t = max(0.0, min(1.0, (lum - 0.72) / 0.28)) * hi_mix
                nr = int(top_c[0] * (1 - t) + 245 * t)
                ng = int(top_c[1] * (1 - t) + 248 * t)
                nb = int(top_c[2] * (1 - t) + 255 * t)

            out[off] = max(0, min(255, nr))
            out[off + 1] = max(0, min(255, ng))
            out[off + 2] = max(0, min(255, nb))

        Image.frombytes("RGBA", (w, h), bytes(out)).save(ui_dir / f"button_{name}.png", format="PNG")
        generated += 1
    return generated


def _find_white_splits(img: Image.Image, count: int, axis: int) -> list[int]:
    """在白色背景图集上，在理论均分线附近 ±14% 范围寻找最纯净的白缝切割坐标，避免邻格边缘串格。"""
    rgb = img.convert("RGB")
    w, h = rgb.size
    length = w if axis == 0 else h
    other = h if axis == 0 else w
    px = rgb.load()
    cuts = [0]
    step = length / float(count)
    # 逐列/逐行统计非白像素比例
    for k in range(1, count):
        nom = int(round(k * step))
        lo = max(1, int(round(nom - length * 0.14)))
        hi = min(length - 2, int(round(nom + length * 0.14)))
        best_pos = nom
        best_score = -1.0
        for pos in range(lo, hi + 1):
            white_cnt = 0
            sample_step = max(1, other // 128)
            samples = 0
            for t in range(0, other, sample_step):
                r, g, b = px[pos, t] if axis == 0 else px[t, pos]
                samples += 1
                if r > 240 and g > 240 and b > 240:
                    white_cnt += 1
            # 纯白越多越优先，同分时越靠近均分线越优先
            score = (white_cnt / max(1, samples)) * 1000.0 - abs(pos - nom) * 0.05
            if score > best_score:
                best_score = score
                best_pos = pos
        cuts.append(best_pos)
    cuts.append(length)
    return cuts


def _is_legacy_coin(spec: CellSpec) -> bool:
    """币面已改由 devtools/slice_coins_hd.py 从高清正俯视图切出，这里不再覆盖。"""
    return spec.rel_out.startswith("coins/")


def _slice_one_sheet(src_path: Path, sheet: SheetSpec, out_root: Path) -> int:
    img = Image.open(src_path)
    sw, sh = img.size
    all_transparent_bg = all(c.transparent for c in sheet.cells)
    if all_transparent_bg:
        y_cuts = _find_white_splits(img, sheet.rows, axis=1)
        row_x_cuts = []
        for r in range(sheet.rows):
            row_band = img.crop((0, y_cuts[r], sw, y_cuts[r + 1]))
            row_x_cuts.append(_find_white_splits(row_band, sheet.cols, axis=0))
    else:
        x_cuts = [int(round(i * sw / float(sheet.cols))) for i in range(sheet.cols + 1)]
        y_cuts = [int(round(j * sh / float(sheet.rows))) for j in range(sheet.rows + 1)]
        row_x_cuts = [x_cuts for _ in range(sheet.rows)]

    written = 0
    for idx, spec in enumerate(sheet.cells):
        if _is_legacy_coin(spec):
            continue
        col = idx % sheet.cols
        row = idx // sheet.cols
        x_cuts = row_x_cuts[row]
        box = (x_cuts[col], y_cuts[row], x_cuts[col + 1], y_cuts[row + 1])
        sub = img.crop(box)
        out_img = _fit_transparent_cell(sub, spec) if spec.transparent else _fit_opaque_cell(sub, spec)
        dest = out_root / spec.rel_out
        dest.parent.mkdir(parents=True, exist_ok=True)
        out_img.save(dest, format="PNG")
        written += 1
    return written


def slice_all(raw_dir: Path, out_root: Path) -> tuple[int, int]:
    found_sheets = 0
    written_files = 0
    for sheet in SHEETS:
        src_path = raw_dir / sheet.filename
        if not src_path.is_file():
            continue
        found_sheets += 1
        written_files += _slice_one_sheet(src_path, sheet, out_root)

    # 若存在返工整合图 sheet_09_rework.png，则优先覆盖对应贴图后再衍生 6 色按钮
    rework_path = raw_dir / REWORK_SHEET.filename
    if rework_path.is_file():
        written_files += _slice_one_sheet(rework_path, REWORK_SHEET, out_root)

    # 由 ui/button.png 衍生 6 色主题按钮图
    written_files += _generate_button_variants(out_root / "ui" / "button.png", out_root / "ui")
    return found_sheets, written_files


def build_qa_contact_sheet(out_root: Path, qa_path: Path) -> None:
    """将全部分片贴在深蓝夜底 #0A0C1A 上供肉眼检查白边/裁切/比例。"""
    entries: list[tuple[str, Path]] = []
    for sheet in SHEETS:
        for spec in sheet.cells:
            p = out_root / spec.rel_out
            if p.is_file():
                entries.append((spec.rel_out, p))
    for v in BUTTON_VARIANTS:
        p = out_root / "ui" / f"button_{v}.png"
        if p.is_file():
            entries.append((f"ui/button_{v}.png", p))

    cols = 9
    cell_w, cell_h = 156, 154
    rows = max(1, (len(entries) + cols - 1) // cols)
    canvas = Image.new("RGB", (cols * cell_w, rows * cell_h), (10, 12, 26))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()

    for i, (label, path) in enumerate(entries):
        c = i % cols
        r = i // cols
        x0 = c * cell_w
        y0 = r * cell_h
        draw.rectangle((x0 + 2, y0 + 2, x0 + cell_w - 3, y0 + cell_h - 3), outline=(42, 54, 96), fill=(18, 22, 46))
        im = Image.open(path).convert("RGBA")
        iw, ih = im.size
        box_w, box_h = cell_w - 18, cell_h - 34
        sc = min(box_w / max(1, iw), box_h / max(1, ih))
        rw, rh = max(1, int(round(iw * sc))), max(1, int(round(ih * sc)))
        thumb = im.resize((rw, rh), Image.Resampling.LANCZOS)
        px = x0 + (cell_w - rw) // 2
        py = y0 + 6 + (box_h - rh) // 2
        canvas.paste(thumb, (px, py), thumb)
        short = label.split("/")[-1].replace(".png", "")
        draw.text((x0 + 6, y0 + cell_h - 20), short[:20], fill=(190, 224, 255), font=font)

    qa_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(qa_path, format="PNG")
    print(f"[OK] QA 总览图已生成: {qa_path} ({len(entries)} 项)")


def run_self_test() -> None:
    tmp = Path(tempfile.mkdtemp(prefix="slice_sheets_test_"))
    try:
        raw = tmp / "raw"
        out = tmp / "out"
        raw.mkdir(parents=True, exist_ok=True)
        for s_idx, sheet in enumerate(SHEETS):
            cw, ch = 320, 320
            img = Image.new("RGBA", (cw * sheet.cols, ch * sheet.rows), (255, 255, 255, 255))
            draw = ImageDraw.Draw(img)
            for idx, spec in enumerate(sheet.cells):
                col = idx % sheet.cols
                row = idx // sheet.cols
                x0, y0 = col * cw, row * ch
                if spec.transparent:
                    draw.ellipse((x0 + 48, y0 + 48, x0 + cw - 48, y0 + ch - 48), fill=(40 + s_idx * 20, 180, 240, 255), outline=(9, 11, 22, 255), width=8)
                    draw.ellipse((x0 + 110, y0 + 95, x0 + 170, y0 + 145), fill=(255, 255, 255, 255))
                else:
                    draw.rectangle((x0, y0, x0 + cw, y0 + ch), fill=(18, 22, 52, 255))
                    draw.rectangle((x0 + 40, y0 + 40, x0 + cw - 40, y0 + ch - 40), fill=(255, 210, 64, 255))
            img.convert("RGB").save(raw / sheet.filename, format="PNG")

        sheets_n, files_n = slice_all(raw, out)
        expected_base = sum(1 for s in SHEETS for c in s.cells if not _is_legacy_coin(c))
        expected_total = expected_base + len(BUTTON_VARIANTS)
        assert sheets_n == len(SHEETS), f"expected {len(SHEETS)} sheets, got {sheets_n}"
        assert files_n == expected_total == 47, f"expected 47 outputs, got {files_n}"
        for sheet in SHEETS:
            for spec in sheet.cells:
                p = out / spec.rel_out
                if _is_legacy_coin(spec):
                    assert not p.exists(), f"legacy coin should be skipped: {p}"
                    continue
                assert p.is_file(), f"missing {p}"
                im = Image.open(p)
                assert im.size == (spec.width, spec.height), f"{p} size {im.size} != {(spec.width, spec.height)}"
                if spec.transparent and not spec.stretch_fill:
                    assert im.mode == "RGBA", f"{p} mode {im.mode} != RGBA"
                    a = im.getchannel("A")
                    assert a.getpixel((0, 0)) == 0, f"{p} corner not transparent"
                    assert a.getpixel((spec.width // 2, spec.height // 2)) > 200, f"{p} center highlight keyed out!"
        for v in BUTTON_VARIANTS:
            assert (out / "ui" / f"button_{v}.png").is_file(), f"missing button_{v}.png"

        # 额外验证：放置 sheet_09_rework.png 时可覆盖对应贴图并重新衍生 6 色按钮
        rw_img = Image.new("RGBA", (640, 320), (255, 255, 255, 255))
        rw_draw = ImageDraw.Draw(rw_img)
        rw_draw.ellipse((48, 48, 272, 272), fill=(255, 210, 64, 255), outline=(9, 11, 22, 255), width=8)
        rw_draw.rounded_rectangle((352, 96, 608, 224), radius=24, fill=(240, 170, 30, 255), outline=(9, 11, 22, 255), width=6)
        rw_img.convert("RGB").save(raw / REWORK_SHEET.filename, format="PNG")
        sheets_n2, files_n2 = slice_all(raw, out)
        assert sheets_n2 == len(SHEETS)
        assert files_n2 == expected_total + len(REWORK_SHEET.cells)
        assert Image.open(out / "relics" / "relic_golden_pegs.png").size == (192, 192)
        assert Image.open(out / "ui" / "button_dark.png").size == (144, 48)
        print(f"SLICE_SHEETS SELF-TEST PASS: {sheets_n} sheets -> {files_n} PNGs + rework sheet verified")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Slice 8 combined sheets into all 66+ assets/image PNGs.")
    root = Path(__file__).resolve().parent.parent
    parser.add_argument("--raw-dir", type=Path, default=root / "devtools" / "raw_sheets")
    parser.add_argument("--out-dir", type=Path, default=root / "assets" / "image")
    parser.add_argument("--qa-sheet", type=Path, default=None)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        return

    if not args.raw_dir.exists():
        print(f"[INFO] 尚未创建原图目录: {args.raw_dir}")
        return

    sheets_n, files_n = slice_all(args.raw_dir, args.out_dir)
    print(f"[OK] 已切分 {sheets_n}/{len(SHEETS)} 张拼图，共输出 {files_n} 张贴图至 {args.out_dir}")
    if args.qa_sheet:
        build_qa_contact_sheet(args.out_dir, args.qa_sheet)


if __name__ == "__main__":
    main()

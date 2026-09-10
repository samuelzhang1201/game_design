#!/usr/bin/env python3
"""
Azgaar Fantasy Map Generator (.json Full export)  ->  Godot 运行时地图渲染所需的数据资产

产出（全部写进 --out 目录）：
  province_id.png   RGBA8 无损。R+G 编码 cell id (0=水域)，B=省(province)低8位，A=255
  state_id.png      RGBA8。R=state id，G=province id 低8位，B=province id 高8位，A=255
  terrain_id.png    RGBA8。R=地形贴图索引(对应 prompt 库的 T-01~T-20)，其余通道留空
  heightmap.png     RGBA8。R=高度(0-255)，海平面 = HEIGHT_SEA_LEVEL 换算值
  province_table.json  每个陆地 cell 的完整属性 + 邻接表
  rivers.json / routes.json / burgs.json / meta.json

用法：
  python azgaar_to_godot.py MAP.json --out ./out --width 4096
"""
import argparse, json, os, sys
from collections import defaultdict

import numpy as np
from PIL import Image, ImageDraw

# ---------------------------------------------------------------- 配置

SEA_LEVEL = 20          # Azgaar 约定：h < 20 为水域

# Azgaar biome index -> prompt 库里的地形贴图编号 (T-xx 的 xx)
BIOME_TO_TILE = {
    0:  17,   # Marine                    -> T-17 深海
    1:  12,   # Hot desert                -> T-12 沙漠
    2:  11,   # Cold desert               -> T-11 干草原
    3:  11,   # Savanna                   -> T-11 干草原
    4:   5,   # Grassland                 -> T-05 草地牧场
    5:   3,   # Tropical seasonal forest  -> T-03 疏林与灌木
    6:   1,   # Temperate deciduous forest-> T-01 温带阔叶林
    7:   1,   # Tropical rainforest       -> T-01 温带阔叶林（缺热带林贴图，见 meta.warnings）
    8:   2,   # Temperate rainforest      -> T-02 针叶林
    9:   2,   # Taiga                     -> T-02 针叶林
    10: 13,   # Tundra                    -> T-13 苔原
    11: 19,   # Glacier                   -> T-19 冰川
    12: 10,   # Wetland                   -> T-10 沼泽湿地
}
TILE_SHALLOW_SEA = 16   # T-16 浅海
TILE_DEEP_SEA    = 17   # T-17 深海
TILE_LAKE        = 18   # T-18 河流与湖泊
TILE_HILLS       = 7    # T-07 丘陵
TILE_MOUNTAIN    = 8    # T-08 山地
TILE_ALPINE      = 9    # T-09 高山雪线

# 高度覆盖阈值（Azgaar 0-100 尺度）。设为 None 关闭覆盖，纯靠 heightmap 做晕滃
H_HILLS    = 45
H_MOUNTAIN = 62
H_ALPINE   = 80
# 这些 biome 不被高度覆盖（沼泽/冰川本身就是决定性地貌）
NO_HEIGHT_OVERRIDE = {11, 12}


# ---------------------------------------------------------------- 主流程

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="Azgaar 导出的 Full .json")
    ap.add_argument("--out", default="./out")
    ap.add_argument("--width", type=int, default=4096, help="输出贴图宽度(px)")
    ap.add_argument("--no-crop", action="store_true", help="不裁剪四周空白")
    ap.add_argument("--crop-margin", type=int, default=48, help="裁剪时保留的公海边距(px)")
    ap.add_argument("--no-height-override", action="store_true",
                    help="不用高度覆盖地形贴图，山地丘陵完全交给 shader 的晕滃层")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    data = json.load(open(args.src, encoding="utf-8"))
    pack = data["pack"]
    info = data["info"]

    src_w, src_h = float(info["width"]), float(info["height"])
    scale = args.width / src_w
    W = args.width
    H = max(1, int(round(src_h * scale)))
    print(f"源画布 {src_w:.0f}x{src_h:.0f}  ->  输出 {W}x{H}  (scale={scale:.4f})")

    cells = pack["cells"]
    verts = pack["vertices"]
    n_cells = max(c["i"] for c in cells) + 1

    # 顶点坐标 -> 输出像素坐标
    vx = np.zeros(max(v["i"] for v in verts) + 1, dtype=np.float64)
    vy = np.zeros_like(vx)
    for v in verts:
        vx[v["i"]] = v["p"][0] * scale
        vy[v["i"]] = v["p"][1] * scale

    # ---------- 1. 把 Voronoi cell 光栅化成一张 cell-id 图（唯一真相来源）----------
    # 用 PIL 的 "I" 模式（32 位整数）直接把 id 画进像素，避免任何颜色量化
    canvas = Image.new("I", (W, H), 0)
    draw = ImageDraw.Draw(canvas)
    degenerate = 0
    for c in cells:
        vs = c.get("v") or []
        pts = [(vx[k], vy[k]) for k in vs if 0 <= k < len(vx)]
        if len(pts) < 3:
            degenerate += 1
            continue
        # fill + outline 同值：闭合相邻多边形之间的 1px 光栅缝隙
        draw.polygon(pts, fill=c["i"], outline=c["i"])
    cell_raster = np.array(canvas, dtype=np.int32)
    covered = cell_raster != 0
    n_open = int((~covered).sum())
    print(f"光栅化完成：{len(cells)} 个 cell（{degenerate} 个退化跳过）")
    print(f"  Voronoi 覆盖 {100 * covered.mean():.1f}%%，"
          f"其余 {n_open} px 视为图外公海（fill+outline 保证内部无缝隙）")

    # 可选：裁掉四周多余的空白，省显存
    ox, oy = 0, 0
    if not args.no_crop:
        ys, xs = np.where(covered)
        m = args.crop_margin
        x0 = max(0, int(xs.min()) - m); x1 = min(W, int(xs.max()) + 1 + m)
        y0 = max(0, int(oy) + int(ys.min()) - m); y1 = min(H, int(ys.max()) + 1 + m)
        if (x1 - x0, y1 - y0) != (W, H):
            cell_raster = cell_raster[y0:y1, x0:x1]
            covered = covered[y0:y1, x0:x1]
            ox, oy = x0, y0
            H, W = cell_raster.shape
            print(f"  裁剪到 {W}x{H}（原点偏移 {ox},{oy}，边距 {m}px）")

    # ---------- 2. 建 cell -> 属性 的查表数组 ----------
    lut_h        = np.zeros(n_cells, dtype=np.uint8)
    lut_biome    = np.zeros(n_cells, dtype=np.uint8)
    lut_state    = np.zeros(n_cells, dtype=np.uint8)
    lut_province = np.zeros(n_cells, dtype=np.uint16)
    lut_is_land  = np.zeros(n_cells, dtype=bool)
    lut_feature  = np.zeros(n_cells, dtype=np.uint8)

    for c in cells:
        i = c["i"]
        lut_h[i]        = min(255, int(round(c["h"] * 255 / 100)))
        lut_biome[i]    = c.get("biome", 0)
        lut_state[i]    = min(255, c.get("state", 0))
        lut_province[i] = c.get("province", 0)
        lut_is_land[i]  = c["h"] >= SEA_LEVEL
        lut_feature[i]  = min(255, c.get("f", 0))

    # feature 类型（区分海洋 / 湖泊）
    feat_type = {}
    for f in pack.get("features", []):
        if isinstance(f, dict):
            feat_type[f.get("i", -1)] = f.get("type", "")

    # ---------- 3. 地形贴图索引 ----------
    lut_tile = np.zeros(n_cells, dtype=np.uint8)
    for c in cells:
        i, h, b = c["i"], c["h"], c.get("biome", 0)
        if h < SEA_LEVEL:
            ft = feat_type.get(c.get("f", 0), "")
            if ft == "lake":
                lut_tile[i] = TILE_LAKE
            else:
                lut_tile[i] = TILE_SHALLOW_SEA if h >= SEA_LEVEL - 6 else TILE_DEEP_SEA
            continue
        t = BIOME_TO_TILE.get(b, 5)
        if not args.no_height_override and b not in NO_HEIGHT_OVERRIDE:
            if   h >= H_ALPINE:   t = TILE_ALPINE
            elif h >= H_MOUNTAIN: t = TILE_MOUNTAIN
            elif h >= H_HILLS:    t = TILE_HILLS
        lut_tile[i] = t

    # ---------- 4. 生成四张数据图 ----------
    # cell id 0 = 图外公海：深海、高度 0、无归属
    lut_is_land[0] = False
    lut_tile[0]    = TILE_DEEP_SEA
    lut_h[0]       = 0
    lut_state[0]   = 0
    lut_province[0] = 0
    lut_biome[0]   = 0

    land_mask_raster = lut_is_land[cell_raster]
    # 水域的 cell id 归零，让 shader 一眼分辨陆海
    pid = np.where(land_mask_raster, cell_raster, 0).astype(np.uint32)

    province_id_png = np.zeros((H, W, 4), dtype=np.uint8)
    province_id_png[..., 0] = (pid & 0xFF).astype(np.uint8)          # cell id 低 8 位
    province_id_png[..., 1] = ((pid >> 8) & 0xFF).astype(np.uint8)   # cell id 高 8 位
    province_id_png[..., 2] = (lut_province[cell_raster] & 0xFF).astype(np.uint8)
    province_id_png[..., 3] = 255
    _save(province_id_png, args.out, "province_id.png")

    prov_r = lut_province[cell_raster].astype(np.uint32)
    state_png = np.zeros((H, W, 4), dtype=np.uint8)
    state_png[..., 0] = lut_state[cell_raster]
    state_png[..., 1] = (prov_r & 0xFF).astype(np.uint8)
    state_png[..., 2] = ((prov_r >> 8) & 0xFF).astype(np.uint8)
    state_png[..., 3] = 255
    _save(state_png, args.out, "state_id.png")

    terr = np.zeros((H, W, 4), dtype=np.uint8)
    terr[..., 0] = lut_tile[cell_raster]
    terr[..., 1] = lut_biome[cell_raster]
    terr[..., 2] = land_mask_raster.astype(np.uint8) * 255
    terr[..., 3] = 255
    _save(terr, args.out, "terrain_id.png")

    hm = np.zeros((H, W, 4), dtype=np.uint8)
    hm[..., 0] = lut_h[cell_raster]
    hm[..., 1] = lut_h[cell_raster]
    hm[..., 2] = lut_h[cell_raster]
    hm[..., 3] = 255
    _save(hm, args.out, "heightmap.png")

    # ---------- 5. 邻接表 + cell 属性表 ----------
    prov_meta = {p["i"]: p for p in pack["provinces"] if isinstance(p, dict)}
    state_meta = {s["i"]: s for s in pack["states"] if isinstance(s, dict)}
    burg_by_cell = {}
    for b in pack["burgs"]:
        if isinstance(b, dict) and b.get("i"):
            burg_by_cell[b["cell"]] = b["i"]

    table = []
    for c in cells:
        if c["h"] < SEA_LEVEL:
            continue
        i = c["i"]
        nb = [k for k in (c.get("c") or []) if 0 <= k < n_cells and lut_is_land[k]]
        p = prov_meta.get(c.get("province", 0), {})
        table.append({
            "id": i,
            "province": c.get("province", 0),
            "province_name": p.get("fullName") or p.get("name") or "",
            "state": c.get("state", 0),
            "state_name": (state_meta.get(c.get("state", 0), {}) or {}).get("name", ""),
            "culture": c.get("culture", 0),
            "religion": c.get("religion", 0),
            "biome": c.get("biome", 0),
            "terrain_tile": int(lut_tile[i]),
            "height": c["h"],
            "pop": round(c.get("pop", 0), 3),
            "area": c.get("area", 0),
            "burg": burg_by_cell.get(i, 0),
            "harbor": c.get("harbor", 0),
            "river": c.get("r", 0),
            "centroid": [round(c["p"][0] * scale - ox, 1), round(c["p"][1] * scale - oy, 1)],
            "neighbours": nb,
        })
    _json(table, args.out, "province_table.json")

    # ---------- 6. 线要素与点要素 ----------
    cell_pt = {c["i"]: c["p"] for c in cells}
    rivers = []
    for r in pack.get("rivers", []):
        pts = [[round(cell_pt[k][0] * scale - ox, 1), round(cell_pt[k][1] * scale - oy, 1)]
               for k in r.get("cells", []) if k in cell_pt]
        if len(pts) >= 2:
            rivers.append({"id": r["i"], "name": r.get("name", ""),
                           "type": r.get("type", ""), "width": r.get("width", 0),
                           "discharge": r.get("discharge", 0), "points": pts})
    _json(rivers, args.out, "rivers.json")

    routes = []
    for rt in pack.get("routes", []):
        pts = [[round(p[0] * scale - ox, 1), round(p[1] * scale - oy, 1)] for p in rt.get("points", [])]
        if len(pts) >= 2:
            routes.append({"id": rt["i"], "group": rt.get("group", ""),
                           "name": rt.get("name", ""), "points": pts})
    _json(routes, args.out, "routes.json")

    burgs = []
    for b in pack["burgs"]:
        if not isinstance(b, dict) or not b.get("i"):
            continue
        burgs.append({
            "id": b["i"], "name": b.get("name", ""), "cell": b.get("cell", 0),
            "state": b.get("state", 0), "culture": b.get("culture", 0),
            "capital": b.get("capital", 0), "port": 1 if b.get("port") else 0,
            "population": b.get("population", 0), "type": b.get("type", ""),
            "group": b.get("group", ""),
            "citadel": b.get("citadel", 0), "walls": b.get("walls", 0),
            "temple": b.get("temple", 0), "plaza": b.get("plaza", 0),
            "pos": [round(b["x"] * scale - ox, 1), round(b["y"] * scale - oy, 1)],
            # 按人口给出建议使用的聚落图标（对应 prompt 库 I-01~I-05）
            "icon": _settlement_icon(b),
        })
    _json(burgs, args.out, "burgs.json")

    # ---------- 7. meta ----------
    warn = []
    used_biomes = set(int(x) for x in np.unique(lut_biome[[c["i"] for c in cells if c["h"] >= SEA_LEVEL]]))
    if 7 in used_biomes:
        warn.append("地图含 Tropical rainforest，已临时映射到 T-01 温带阔叶林；"
                    "若这片区域重要，建议补一张热带雨林贴图。")
    meta = {
        "source": {"generator": "Azgaar FMG", "version": info.get("version"),
                   "mapName": info.get("mapName"), "seed": info.get("seed"),
                   "exportedAt": info.get("exportedAt")},
        "raster": {"width": W, "height": H, "scale": scale,
                   "crop_offset": [ox, oy],
                   "src_width": src_w, "src_height": src_h,
                   "note": "所有 json 里的坐标已是最终贴图像素坐标（含裁剪偏移），可直接用"},
        "encoding": {
            "province_id.png": "R + G<<8 = cell id (0 = 水域); B = province id 低8位",
            "state_id.png": "R = state id; G + B<<8 = province id",
            "terrain_id.png": "R = 地形贴图索引 (T-xx); G = Azgaar biome id; B = 陆地掩码(255=陆)",
            "heightmap.png": "R/G/B = 高度 0-255, 海平面 = %d" % round(SEA_LEVEL * 255 / 100),
        },
        "counts": {"cells": len(cells), "land_cells": int(lut_is_land.sum()),
                   "provinces": len([p for p in pack["provinces"] if isinstance(p, dict)]),
                   "states": len([s for s in pack["states"] if isinstance(s, dict)]),
                   "burgs": len(burgs), "rivers": len(rivers), "routes": len(routes)},
        "states": [{"id": s["i"], "name": s.get("name", ""), "color": s.get("color"),
                    "capital_burg": s.get("capital", 0), "cells": s.get("cells", 0)}
                   for s in pack["states"] if isinstance(s, dict)],
        "provinces": [{"id": p["i"], "name": p.get("name", ""),
                       "full_name": p.get("fullName", ""), "state": p.get("state", 0),
                       "color": p.get("color"), "burg": p.get("burg", 0),
                       "pole": p.get("pole")}
                      for p in pack["provinces"] if isinstance(p, dict)],
        "biome_to_tile": {str(k): v for k, v in BIOME_TO_TILE.items()},
        "biomes": [{"id": b["i"], "name": b["name"], "color": b["color"]}
                   for b in pack["biomes"]],
        "warnings": warn,
    }
    _json(meta, args.out, "meta.json")

    # ---------- 8. 预览图（人工核对用，不是游戏资产）----------
    _preview(cell_raster, lut_is_land, lut_state, lut_tile, lut_h,
             meta["states"], burgs, args.out)

    print("\n完成。产物：")
    for f in sorted(os.listdir(args.out)):
        print(f"  {f:<24} {os.path.getsize(os.path.join(args.out, f)) / 1024:>10.1f} KB")
    for w in warn:
        print("\n⚠ " + w)
    return 0


# ---------------------------------------------------------------- 工具

def _preview(cell_raster, is_land, state, tile, height, states, burgs, out):
    """把转换结果画成一张人眼可读的图，用来确认海陆、国界、地形没错位。"""
    H, W = cell_raster.shape
    img = np.zeros((H, W, 3), dtype=np.uint8)

    land = is_land[cell_raster]
    h = height[cell_raster].astype(np.float32) / 255.0

    # 海：按深度渐变
    sea = np.stack([ (40 + 60 * h), (80 + 70 * h), (130 + 60 * h) ], axis=-1)
    img[~land] = np.clip(sea[~land], 0, 255).astype(np.uint8)

    # 陆：国家色 × 高度明暗
    scol = np.full((256, 3), 200, dtype=np.uint8)
    for s_ in states:
        c = s_.get("color") or "#999999"
        if isinstance(c, str) and c.startswith("#") and len(c) == 7:
            scol[s_["id"]] = [int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16)]
    base = scol[state[cell_raster]].astype(np.float32)
    shade = (0.55 + 0.9 * h)[..., None]
    img[land] = np.clip(base * shade, 0, 255).astype(np.uint8)[land]

    # 国界：邻域 state 不同就描黑
    st = state[cell_raster]
    edge = np.zeros((H, W), bool)
    edge[:, :-1] |= st[:, :-1] != st[:, 1:]
    edge[:-1, :] |= st[:-1, :] != st[1:, :]
    img[edge & land] = [30, 25, 20]

    # 海岸线
    coast = np.zeros((H, W), bool)
    coast[:, :-1] |= land[:, :-1] != land[:, 1:]
    coast[:-1, :] |= land[:-1, :] != land[1:, :]
    img[coast] = [25, 30, 45]

    im = Image.fromarray(img, "RGB")
    dr = ImageDraw.Draw(im)
    for b in burgs:
        x, y = b["pos"]
        r = 4 if b["capital"] else 2
        dr.ellipse([x - r, y - r, x + r, y + r],
                   fill=(255, 240, 200) if b["capital"] else (245, 225, 180),
                   outline=(40, 30, 20))
    im.save(os.path.join(out, "_preview.png"), optimize=True)


def _settlement_icon(b: dict) -> str:
    """按人口和特征给出 prompt 库里的聚落/城堡图标编号。"""
    pop = b.get("population", 0)
    if b.get("capital"):
        return "I-05"                      # 大都会
    if pop >= 20:
        return "I-04"                      # 城市
    if pop >= 6:
        return "I-03"                      # 集镇
    if pop >= 2:
        return "I-02"                      # 村庄
    return "I-01"                          # 农庄


def _save(arr: np.ndarray, out: str, name: str) -> None:
    Image.fromarray(arr, mode="RGBA").save(os.path.join(out, name), optimize=True)


def _json(obj, out: str, name: str) -> None:
    with open(os.path.join(out, name), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    sys.exit(main())

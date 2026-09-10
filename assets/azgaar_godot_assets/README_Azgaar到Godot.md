# Azgaar → Godot：不需要 GIS 了

> **结论**：你的 Azgaar 导出文件比 GIS 数据更适合这个项目。GIS 那条线可以整条删掉。

---

## 1. 为什么 Azgaar 直接取代 GIS

之前引入 GIS 是为了解决「真实比例 + 真实地理」。现在两个前提都没了：

| 需求 | GIS 方案 | Azgaar 方案 |
|---|---|---|
| 海岸线 / 河流形状 | Natural Earth 矢量 | **已经有了**，而且是自洽的幻想大陆 |
| 高程 | SRTM / GEBCO 栅格 | 每个 cell 一个 `h` 值（0–100） |
| 省份划分 | 要手绘 2000 个 | **已经有了 3500 个陆地 cell** |
| 政治归属 | 要自己造 | 8 个国家、204 个省，已分配好 |
| 城镇 | 要自己摆 | 686 个 burg，带人口、类型、城墙/城堡/神庙标记 |
| 地形分类 | 要自己画 landcover | 13 种 biome 已分好 |
| 河流 | 要自己描 | 180 条，带流量、宽度、上下游关系 |
| 道路 | 要自己连 | 557 条（11 条大道 + 419 条小径 + 127 条海路） |
| 文化 / 宗教 | 要自己造 | 4 种文化、6 种宗教，已按 cell 分布 |
| 地名 | 要自己起 | 全部已生成 |

GIS 给你的是「真实但没有游戏内容的地球」。Azgaar 给你的是「一个已经填满内容的世界」。对大战略游戏来说后者价值高一个数量级。

**唯一的取舍**：地理是虚构的。但你已经明确「不用真实比例，可玩性优先」，所以这不是损失。

---

## 2. 你这张图有什么

```
Game_dev  ·  Azgaar FMG 1.151.2  ·  seed 954159497  ·  画布 2560×929
```

| 项 | 数量 | 说明 |
|---|---|---|
| Voronoi cell | 4833 | 其中 **3500 陆地** / 1333 水域 |
| 国家 (states) | 8 | Irongate 800 cells 最大，Valmoor 61 最小 |
| 省 (provinces) | 204 | 每省覆盖约 17 个 cell |
| 城镇 (burgs) | 686 | 含 7 个首都；带 citadel/walls/temple/plaza 标记 |
| 河流 | 180 | 带流量、宽度、干支流关系 |
| 路线 | 557 | roads 11 / trails 419 / searoutes 127 |
| 文化 | 4 | 宗教 6 |
| 岛屿 / 湖泊 | 12 / 4 | |
| 商品 / 市场 / 贸易协议 | 71 / 27 / 10844 | 经济系统可以直接接 |
| 笔记 | 132 条 | 已生成的地点描述文本 |

### 天然的三层封建层级

这一点非常适合你的题材，等于白送一套政治结构：

```
state    (8)      →  王国 / 公国        ← 玩家扮演的层级
  province (204)  →  伯爵领 / 郡
    cell   (3500) →  男爵领 / 具体地块   ← 军队移动、地形、建筑的最小单位
```

CK3 就是这个结构（帝国 / 王国 / 公国 / 伯爵领 / 男爵领）。3500 个地块的规模接近 EU4，对独立团队偏大但完全可以先只用 province 层做玩法、cell 层只做地形和移动。

---

## 3. 转换器

`azgaar_to_godot.py` —— 纯 Python（numpy + Pillow），不依赖 Godot 也不依赖 GIS 库。

```bash
python azgaar_to_godot.py Game_dev.json --out ./out --width 4096
```

| 参数 | 说明 |
|---|---|
| `--width` | 输出贴图宽度，默认 4096 |
| `--crop-margin` | 裁掉图外公海时保留的边距，默认 48px |
| `--no-crop` | 不裁剪，保持原始画布比例 |
| `--no-height-override` | 不用高度覆盖地形贴图，山地丘陵完全交给 shader 晕滃层 |

### 产出

实测输出 **3615×1476**（4096 宽光栅化后裁掉了图外公海）：

| 文件 | 编码 | 大小 |
|---|---|---|
| `province_id.png` | **R + G<<8 = cell id**（0 = 水域）；B = province id 低 8 位 | 258 KB |
| `state_id.png` | R = state id；**G + B<<8 = province id** | 104 KB |
| `terrain_id.png` | R = 地形贴图编号 (T-xx)；G = Azgaar biome id；**B = 陆地掩码** | 148 KB |
| `heightmap.png` | R/G/B = 高度 0–255（海平面 = 51） | 298 KB |
| `province_table.json` | 3500 条：id / 省 / 国 / 文化 / 宗教 / biome / 地形 / 高度 / 人口 / 城镇 / 质心 / **邻接表** | 959 KB |
| `burgs.json` | 686 个城镇，含建议使用的图标编号 (`I-01`~`I-05`) | 143 KB |
| `rivers.json` / `routes.json` | 折线坐标，已是最终贴图像素坐标 | 29 / 80 KB |
| `meta.json` | 尺寸、编码说明、国家/省份名录与配色、biome→贴图映射 | 25 KB |
| `_preview.png` | **人工核对用的预览图**，不是游戏资产 | 377 KB |

**全部数据图加起来 808 KB**，解压进显存约 85 MB。

> 所有 json 里的坐标**已经是最终贴图的像素坐标**（裁剪偏移已算进去），在 Godot 里可以直接用，不需要再做任何变换。

---

## 4. 验证结果

转换器的输出做过完整交叉校验：

| 检查 | 结果 |
|---|---|
| Voronoi 光栅化内部缝隙 | **0 像素**（fill + outline 同值闭合了相邻多边形的缝） |
| cell id 编解码往返 | 栅格中 3500 个 cell，与表中 3500 条完全一一对应 |
| province / state 解码 | state 0–7、province ≤ 203，与源数据一致 |
| 高度图 vs 属性表 | 抽查 300 个 cell 质心，**0 处不一致** |
| 邻接表对称性 | **0 条非对称边**，平均 5.52 个邻居（Voronoi 的合理值） |
| 城镇落点 | 686 个中 651 个精确落在自身 cell 上 |

### 关于那 35 个「落点不符」的城镇

全部是**港口**：Azgaar 把港口城镇的坐标放在海岸线上，四舍五入后那个像素落在水侧（33 个）或相邻 cell（2 个）。**没有一个是真正的错位。**

→ **Godot 里要用 `burgs.json` 的 `cell` 字段来确定城镇归属，不要去采样栅格。** 栅格是给 shader 用的，归属关系以 json 为准。

---

## 5. 只需要做 14 张地形贴图（不是 20 张）

这张图实际用到的贴图，按覆盖面积排序：

| 贴图 | 占比 | 优先级 |
|---|---|---|
| `T-17` 深海 | 37.3% | ⭐ 先做 |
| `T-16` 浅海 | 27.4% | ⭐ 先做 |
| `T-07` 丘陵 | 7.7% | ⭐ 先做 |
| `T-01` 温带阔叶林 | 7.1% | ⭐ 先做 |
| `T-02` 针叶林 | 6.3% | ⭐ 先做 |
| `T-05` 草地牧场 | 4.0% | |
| `T-08` 山地 | 3.2% | |
| `T-11` 干草原 | 2.5% | |
| `T-10` 沼泽湿地 | 2.0% | |
| `T-03` 疏林灌木 | 1.5% | |
| `T-19` 冰川 | 0.4% | 可后做 |
| `T-09` 高山雪线 | 0.4% | 可后做 |
| `T-18` 河流湖泊 | 0.1% | 可后做 |
| `T-13` 苔原 | 0.05% | 可后做 |

**前 5 张覆盖 85.8% 的画面。** 先把这 5 张做到最好，整张地图的观感就成立了。

**本图不需要生成**：`T-04` 耕地条田、`T-06` 荒原石楠、`T-12` 沙漠、`T-14` 葡萄园、`T-15` 橄榄果园、`T-20` 焦土废墟。

> ⚠ 但 **`T-04` 耕地条田不该丢**。Azgaar 没有「农田」这个 biome，可 中世纪题材里城镇周围的条田是最有辨识度的地貌之一。做法：**在 shader 里按「距最近 burg 的距离 + cell 人口」动态混入耕地贴图**，而不是当成一种 biome。同理 `T-20` 焦土废墟留给战争系统运行时叠加。

---

## 6. Shader 需要改的地方

相对《Godot 地图渲染架构》那份文档，编码变了（多了一层 cell/province/state），shader 前半段改成：

```glsl
uniform sampler2D province_id_map : filter_nearest, repeat_disable; // R+G=cell, B=province低8位
uniform sampler2D state_id_map    : filter_nearest, repeat_disable; // R=state, G+B=province
uniform sampler2D terrain_id_map  : filter_nearest, repeat_disable; // R=tile, G=biome, B=land mask

// 三层查找表，对应三个层级的地图模式
uniform sampler2D cell_lut     : filter_nearest, repeat_disable;  // 256x256 → 65536 个 cell
uniform sampler2D province_lut : filter_nearest, repeat_disable;  // 16x16 够 204 个省，用 256x256 省事
uniform sampler2D state_lut    : filter_nearest, repeat_disable;

uniform int border_level = 1;   // 0=cell边界 1=省界 2=国界

uint decode_cell(vec2 uv) {
    vec2 rg = texture(province_id_map, uv).rg;
    return uint(rg.r * 255.0 + 0.5) + uint(rg.g * 255.0 + 0.5) * 256u;
}

uint decode_province(vec2 uv) {
    vec3 s = texture(state_id_map, uv).rgb;
    return uint(s.g * 255.0 + 0.5) + uint(s.b * 255.0 + 0.5) * 256u;
}

uint decode_state(vec2 uv) {
    return uint(texture(state_id_map, uv).r * 255.0 + 0.5);
}

// 按当前 zoom / 地图模式决定画哪一级边界
uint border_key(vec2 uv) {
    if (border_level == 0) return decode_cell(uv);
    if (border_level == 1) return decode_province(uv);
    return decode_state(uv);
}
```

`fragment()` 里把原来的 `pid` 换成 `border_key(juv)` 做边界检测，颜色查表则按当前地图模式选 `cell_lut` / `province_lut` / `state_lut`。

**这样一套 shader 同时支持三级边界**：远景只画国界，中景画省界，近景画 cell 界。用 `zoom_t` 驱动 `border_level` 即可，这正是 CK3 的行为。

陆海判定直接用 `terrain_id_map` 的 B 通道，比判断 cell id 是否为 0 更明确：

```glsl
float is_land = texture(terrain_id_map, juv).b;
```

---

## 7. Godot 侧的数据加载

```gdscript
class_name MapData
extends RefCounted

var cells: Dictionary = {}       # int cell_id -> Dictionary
var burgs: Array[Dictionary] = []
var meta: Dictionary = {}

func load_all(dir: String = "res://map/data/") -> void:
    meta = _read_json(dir + "meta.json")
    for row in _read_json(dir + "province_table.json"):
        cells[int(row["id"])] = row
    burgs.assign(_read_json(dir + "burgs.json"))

func _read_json(path: String) -> Variant:
    var txt := FileAccess.get_file_as_string(path)
    return JSON.parse_string(txt)

## 从屏幕点击定位到 cell —— 采样 province_id.png 的 CPU 副本
func cell_at(px: Vector2i, id_image: Image) -> int:
    if px.x < 0 or px.y < 0 or px.x >= id_image.get_width() or px.y >= id_image.get_height():
        return 0
    var c := id_image.get_pixel(px.x, px.y)
    return c.r8 + c.g8 * 256

## A* 用的邻接
func neighbours_of(cell_id: int) -> Array:
    return cells.get(cell_id, {}).get("neighbours", [])
```

> 点击拾取要保留一份 `province_id.png` 的 CPU 端 `Image`（`texture.get_image()`），不要每次从 GPU 回读。3615×1476 的 `Image` 常驻内存约 21 MB，可以接受。

---

## 8. 保留 GIS 的唯一理由

如果你后来想让世界"看起来更像真实地球"（更自然的海岸线曲折度、更合理的山脉走向），可以拿真实地形当**风格参考**去调 Azgaar 的生成参数，而不是引入 GIS 数据。Azgaar 本身有大量地形笔刷和高度模板。

**换句话说：GIS 那一整条工具链（QGIS / GDAL / Tippecanoe / PMTiles / Natural Earth）现在可以从项目里完全删除。**

---

## 9. 下一步

1. 把 `out/` 里的 4 张 PNG 拖进 Godot，**导入设置改成 Lossless + Mipmaps off**（这一步不做，点击选省一定出错）
2. 搭最小场景：PlaneMesh + shader，先只显示 `state_lut` 的政治色 + 国界
3. 对着 `_preview.png` 核对：海陆、国界、岛屿位置应当完全一致
4. 接入前 5 张地形贴图，看彩铅质感在 shader 里混出来是什么效果
5. 效果确认后，再做剩下 9 张贴图和城镇图标

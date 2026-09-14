# 中世纪大战略游戏 · AI 美术 Prompt 库

> **项目**：中世纪写实大战略（参考 CK3 / 文明6 / 维多利亚3）
> **美术风格**：彩色铅笔手绘插画（colored pencil illustration）
> **年代设定基准**：**公元 1050–1350 年，西欧为核心，边缘涵盖北欧、拜占庭、伊比利亚、黎凡特、草原**
> **本文件用途**：一个 ID = 一个资源对象 = 一条可直接使用的 prompt

---

## 目录

| 章节 | 内容 | 资源数 |
|---|---|---|
| [0. 使用说明](#0-使用说明) | 怎么用这份文件 | — |
| [1. 风格基准](#1-风格基准style-bible) | STYLE_CORE / 负面词 / 参数 / 调色板 | — |
| [2. 人物立绘](#2-人物立绘-c) | `C-01` ~ `C-55` | 55 |
| [3. 表情与姿态差分](#3-表情与姿态差分-e--p) | `E-01`~`E-16`, `P-01`~`P-12` | 28 |
| [4. 世界地图底图](#4-世界地图底图-m) | `M-01` ~ `M-14` | 14 |
| [5. 地形平铺贴图](#5-地形平铺贴图-t) | `T-01` ~ `T-20` | 20 |
| [6. 地图元素与图标](#6-地图元素与图标-i) | `I-01` ~ `I-46`，`D-01` ~ `D-31`（§6.9 手绘装饰件），`G-01` ~ `G-38`（§6.10 经济产物） | 115 |
| [7. 战术地图元素](#7-战术地图元素-w) | `W-01` ~ `W-38` | 38 |
| [8. 事件插图](#8-事件插图-v) | `V-01` ~ `V-34` | 34 |
| [9. UI 框架件](#9-ui-框架件-u) | `U-01` ~ `U-18` | 18 |
| [10. 生产流程与质检](#10-生产流程与质检) | 工作流、排期、checklist | — |

**总计 284 个资源对象。**

---

## 0. 使用说明

### 0.1 每条 prompt 的写法

文件里所有 prompt 都写成这个形式：

```
[S] + <主体描述> + [C] + <画幅/构图>
```

- `[S]` = **STYLE_CORE**，见 1.1，**逐字复制，一个词都不要改**
- `[C]` = **CAMERA/CANVAS**，见 1.3，按资源类型选
- 中间的主体描述是每条 prompt 独有的部分

**为什么要拆成这样**：风格一致性的唯一可靠保证是「风格描述完全逐字相同」。只要有人手抖改了一个形容词，那批图就会飘。建议把 `[S]` 存成文本片段或 ComfyUI 的一个常量节点，永远从那里引用。

### 0.2 使用顺序（重要）

1. **先跑第 2 章的前 5 个人物 + 第 4 章的 M-01**，只用 `[S]`，不训任何模型。目的是确认 STYLE_CORE 出来的东西你满意。不满意就在这一步改 `[S]`，改完重跑。
2. 风格定稿后，**挑 30–40 张最好的图训一个 style LoRA**（见第 10 章）。
3. **之后所有 prompt 都在 LoRA 下跑**，`[S]` 保留但可以简化为触发词 + 少量关键描述。
4. 主要角色再各训一个 character LoRA，与 style LoRA 叠加使用。

**跳过第 1 步直接批量生成，是这个项目最容易犯的错误。**

### 0.3 命名与文件组织

建议生成后按 ID 归档，方便追溯和重生成：

```
/art
  /characters      C-01_aging-king_v03.png
  /expressions     C-01_E-04_wrathful.png
  /map             M-05_z6-region-basemap.png
  /terrain         T-03_deciduous-forest_tile.png
  /icons           I-12_city-tier4.png
  /tactical        W-07_flanking-arrow.png
  /events          V-01_assassination.png
  /ui              U-03_parchment-panel.png
/prompts
  STYLE_CORE.txt   ← 唯一真相来源
  NEGATIVE.txt
```

---

## 1. 风格基准（Style Bible）

### 1.1 `[S]` STYLE_CORE —— 逐字复制

> **v2（2026-09-11）**：去掉了做旧和重颗粒（antique plate / granular tooth / graphite underdrawing / laid paper），改为干净的彩铅插画风——亮纸底、利落轮廓、排线只做阴影和布料。原因：Klein 4B 把 v1 的做旧词全部执行成了发黄的博物馆画稿，与游戏现有画面不搭；owner 更喜欢 schnell 出的干净版本。v1 原文见附录 A。

```
clean colored pencil illustration on bright smooth cream paper, crisp confident
contour lines in dark umber pencil, light decorative directional hatching used
only for shading, fabrics rendered as smooth woven cloth with clean folds and
no fibrous or fuzzy texture, smooth evenly blended skin, every surface
fully coloured with solid local colour and soft shading, the same painted
treatment for buildings, objects and terrain as for people, no bare unpainted
linework, fresh and luminous, flat clean paper background with no grain and no aging, muted earthen
palette of raw umber, yellow ochre, burnt sienna, moss green, slate blue and
oxblood red, restrained color, warm diffuse overcast daylight, historically
accurate 12th to 14th century European material culture, naturalistic anatomy
and proportion, appealing idealised faces with fine features, youthful where
the age allows, contemporary character concept illustration quality, matte
finish
```

### 1.2 负面 prompt（所有资源通用）

```
digital airbrush, glossy, smooth gradient, neon, oversaturated, high contrast,
anime, manga, cel shading, comic book, 3d render, cgi, plastic, vector art, flat
color fill, thick ink outline, oil painting impasto, watercolor bleed, photograph,
modern clothing, zipper, buttons on medieval garments, eyeglasses, wristwatch,
printed typography, lettering, watermark, signature, logo, lens flare, bokeh, HDR,
fisheye, extra fingers, deformed hands, plate armour before 1400, full gothic
plate, horned helmet, longsword crossguard anachronism, aged paper, foxing,
yellowed paper, heavy grain, smudged graphite, antique print, sepia, coarse
features, haggard, fuzzy fabric, fibrous texture, felted wool, furry cloth, bare line
drawing, unpainted sketch, outline only, pale washed-out, architectural line art
```

### 1.3 `[C]` 画幅与构图片段

| 代号 | 用途 | 片段 |
|---|---|---|
| `[C-PORTRAIT]` | 人物立绘 | `half-length portrait, three-quarter view, centred composition, plain warm cream paper background, subject occupies 70% of frame, 1:1 square` |
| `[C-BUST]` | 对话头像 | `head and shoulders bust, extreme close-up, the face fills the upper two thirds of the frame, frontal three-quarter view, tight crop, vignetted cream paper background, 1:1 square` |
| `[C-FULL]` | 全身立绘 | `full length standing figure shown head to toe with the feet fully inside the frame, slight low angle, plain cream paper ground, no furniture or props touching the ground, thin cast shadow only, 2:3 vertical` |
| `[C-ICON]` | 地图/UI 图标 | `single isolated object, orthographic three-quarter overhead view, no background, no scene, no ground plane, centred, generous margin, 1:1 square` |
| `[C-TILE]` | 可平铺贴图 | `seamless tileable texture, flat top-down orthographic view, even illumination, no directional shadow, no focal point, uniform density across the whole square, 1:1` |
| `[C-MAP]` | 地图底图 | `top-down orthographic cartographic view, north up, no perspective, even lighting, antique map plate` |
| `[C-SCENE]` | 事件插图 | `narrative illustration, cinematic staging, shallow depth of field suggested by softer pencil pressure in background, 3:2 horizontal` |
| `[C-SYMBOL]` | 战术符号 | `flat cartographic symbol, drawn as if inked onto a military campaign map, isolated on transparent background, no scene, no perspective, 1:1 square` |
| `[C-UIPIECE]` | UI 部件（`U-`，2026-09-12） | `a single user interface piece drawn flat and face-on with no perspective, filling the frame edge to edge with only a thin even margin all round, straight true horizontal and vertical edges, standing on a plain flat neutral grey ground clearly separated from the piece itself, no scene, no props, no cast shadow, 1:1 square` |
| `[C-UIWIDE]` | UI 长条部件（`U-03`/`U-08`/`U-13`/`U-17`，用 `--canvas C-UIWIDE`） | `a single wide user interface strip drawn flat and face-on with no perspective, running the full width of the frame with only a thin even margin at each end, straight true horizontal edges, standing on a plain flat neutral grey ground clearly separated from the piece itself, no scene, no props, no cast shadow, 3:1 horizontal` |
| `[C-FRAME]` | 满屏装饰画框（`U-19`，2026-09-12） | `a full-bleed decorative screen border, the ornament confined to a band around the four edges and the corners, the entire middle two thirds left as plain unmarked cream vellum with absolutely nothing drawn on it, symmetrical left to right, no text, 16:9 horizontal` |
| `[C-MAPMARK]` | 手绘地图符号（`D-`，2026-09-12） | `single map symbol drawn in flat side elevation, pure white background, no parchment, nothing at all beneath the object, no ground line, no ground plate, no cast shadow, centred with generous margin, 1:1 square` |
| `[C-ESTATE]` | 庄园彩绘（`B-`，2026-09-14） | `a painted vignette of one rural holding seen from a gentle raised three-quarter view, the whole holding inside the frame with a little ground and sky around it, the edges fading softly into plain cream paper, no text, no border, no frame, 5:4 horizontal` |

### 1.4 调色板（写进美术规范，别让 AI 自由发挥）

| 角色 | 名称 | Hex | 用途 |
|---|---|---|---|
| 纸底 | Cream Laid | `#EDE3CE` | 所有资源的统一底色 |
| 主暗 | Raw Umber | `#5B4636` | 线条、阴影、文字 |
| 主暖 | Yellow Ochre | `#C8973F` | 皮肤、麦田、羊皮纸高光 |
| 次暖 | Burnt Sienna | `#9C5A34` | 木、砖、皮革 |
| 主冷 | Slate Blue | `#5A6B7C` | 水、远山、金属、阴影补色 |
| 植被 | Moss Green | `#6B7A4B` | 林地、草地 |
| 强调 | Oxblood | `#7A2E2B` | 敌对势力、危险、血、王权红 |
| 强调 | Verdigris | `#4E7A6B` | 己方势力、贸易、青铜 |

> **规则**：任何 prompt 都不得引入这 8 色以外的主色。需要区分势力时用**明度和饱和度**变化，不要引入新色相 —— 否则整套地图会花掉。

### 1.5 生成参数建议

| 工具 | 参数 |
|---|---|
| **Flux.1 dev / Flux 2**（推荐主力） | guidance 2.5–3.5（高了会变"数字感"）；steps 28–35；分辨率先出 1024，再用放大 |
| **Qwen-Image** | CFG 3.5–4.5；适合需要画面里有多个人物的事件插图 |
| **Midjourney** | `--style raw --stylize 150 --chaos 5`；`--sref` 锁风格参考图；不要用默认 stylize（会加重数字感） |
| **通用** | **固定 seed 做变体**：同一角色的表情差分务必锁 seed，只改表情词 |
| **放大** | 用保留笔触的放大器（如 SUPIR / 4x-UltraSharp），**不要**用会抹平颗粒的通用超分 |

---

## 2. 人物立绘 `C-`

> **多样性原则**：55 个角色在**年龄（14–75）、性别、体型、地域族裔、社会阶层、情绪基调**六个维度上刻意打散。每个角色都有一个「性格标签」和一个**手部动作**——手是最能传达性格的部位，也是 AI 最容易画崩的部位，所以每条 prompt 都明确指定了手在做什么。
>
> 所有 prompt 默认拼接 `[S]` 开头、`[C-PORTRAIT]` 结尾（另有标注的除外）。
>
> **`**外貌**` 行（2026-09-11 起）**：只写长相和衣着，不写动作、道具、构图。全身立绘和对话头像用它而不是主 prompt 来拼：`[S] + 外貌 + P-xx 姿态 + [C-FULL]`，`[S] + 外貌 + E-xx 表情 + [C-BUST]`。主 prompt 里的王座、酒杯、账簿这类道具在全身像里会变成半截家具，所以要拆开。游戏里实际用的是这两档，`[C-PORTRAIT]` 半身像只用来定风格。

### 2.1 王室与高等贵族

#### `C-01` 年迈的国王 · The Aging King
**性格**：多疑、疲惫、拒绝放权 | **画幅**：`[C-PORTRAIT]`
**外貌**：`a gaunt European king of sixty-eight, deeply lined face, sunken grey eyes under heavy lids, thin white hair under a simple open gold circlet, a sparse white beard, wearing an oxblood wool mantle lined with miniver over a long embroidered tunic with a round neck closed by a gold brooch, a gilded belt, dark hose and black leather turnshoes`
```
[S] a gaunt European king in his late sixties, deeply lined face, sunken grey eyes
under heavy lids, thin white hair pressed flat by a simple open gold circlet, sparse
white beard, wearing a heavy oxblood wool mantle lined with worn miniver fur over a
long embroidered tunic, one liver-spotted hand gripping the arm of a wooden throne so
hard the knuckles blanch, the other resting slack in his lap, mouth set in a hard
downward line, eyes narrowed with suspicion at something off frame, exhausted but
unyielding [C-PORTRAIT]
```

#### `C-02` 算计的王后 · The Calculating Queen
**性格**：冷静、耐心、手腕比国王更硬
**外貌**：`a composed European queen of forty-two, pale oval face with a high plucked forehead, dark steady eyes, hair concealed under a white linen wimple and barbette with a gold fillet, wearing a close-fitted slate blue wool gown with tight buttoned sleeves and a high collar laced at the throat, a woven girdle, long skirts and black leather turnshoes`
```
[S] a composed European queen in her early forties, pale oval face with high forehead
plucked in the fashion of the period, dark eyes steady and unblinking, hair entirely
concealed under a white linen wimple and barbette with a narrow gold fillet, wearing a
close-fitted slate blue gown with tight buttoned sleeves, holding a folded parchment
letter against her chest with both hands, thumb pressed over the broken wax seal, faint
knowing half smile that does not reach her eyes, absolutely still [C-PORTRAIT]
```

#### `C-03` 傲慢的王储 · The Impatient Heir
**性格**：自负、暴躁、能力不配野心
**外貌**：`a European crown prince of twenty-two, flushed cheeks, curled chestnut hair to the jaw, a thin moustache, wearing a fashionable parti-coloured cotehardie in ochre and oxblood with dagged sleeves and a high buttoned collar, a jewelled belt slung low on the hips, parti-coloured hose, a sheathed sword at the hip and pointed leather ankle boots`
```
[S] a European crown prince of twenty-two, handsome in a soft unearned way, flushed
cheeks, curled chestnut hair to the jaw, thin moustache, wearing a fashionable parti
coloured cotehardie in ochre and oxblood with dagged sleeves, a jewelled belt slung low
on the hips, right hand clamped impatiently on the pommel of a sheathed sword, left hand
gesturing dismissively mid sentence, chin raised, eyebrows drawn together in petulant
irritation, leaning back [C-PORTRAIT]
```

#### `C-04` 私生子 · The Bastard Son
**性格**：阴郁、观察者、被排除在外
**外貌**：`a young man of nineteen with the king's exact bone structure but plain undyed clothing, dark hair cut bluntly at the neck, wearing a plain undyed linen tunic with a keyhole neck slit tied by a drawstring and a narrow leather belt, brown hose and soft plain leather turnshoes without laces or decoration, no jewellery whatsoever`
```
[S] a young man of nineteen with the king's exact bone structure but plain undyed
clothing, dark hair cut bluntly at the neck, one shoulder turned away from the viewer as
if caught mid departure, glancing back over that shoulder with guarded resentful eyes,
wearing a coarse brown wool tunic with a plain leather belt and no jewellery whatsoever,
both hands hidden inside his sleeves, jaw tight, standing slightly off centre in the
frame with more empty paper on the side he is turning toward [C-PORTRAIT]
```

#### `C-05` 独眼老公爵 · The One-Eyed Duke
**性格**：暴烈、忠诚、活在过去的战争里
**外貌**：`a broad-shouldered European duke of sixty, weathered red face, a livid scar from the left temple through a milky blind eye to the jaw, iron-grey hair and full beard, wearing a mail hauberk under a faded heraldic surcoat with a neck slit laced at the throat, a sword belt, dark hose and leather riding boots`
```
[S] a broad shouldered European duke of sixty, thick neck, weathered red face, a livid
puckered scar running from left temple through a milky blind eye down to the jaw, iron
grey hair and full beard, wearing a mail hauberk under a faded surcoat with a barely
legible heraldic charge, thick fingers curled around a horn cup, other hand flat on the
table pushing forward, good eye blazing, mouth open mid shout, body leaning aggressively
into the frame [C-PORTRAIT]
```

#### `C-06` 掌权的寡妇伯爵 · The Widowed Countess Regnant
**性格**：精算、克制、不容置疑
**外貌**：`a European noblewoman of fifty, sharp intelligent face, thin lips, crow's feet, dressed entirely in undyed black wool, a black veil over a white linen wimple, a high round neckline fastened with a small jet brooch, a plain leather girdle, long skirts over black hose and black leather turnshoes, a single iron ring on her thumb`
```
[S] a European noblewoman of fifty in mourning, sharp intelligent face, thin lips,
crow's feet, entirely dressed in undyed black wool with a black veil over a white
wimple, a single iron ring on her thumb, one hand holding open a tall narrow account
ledger propped against her forearm, the other hand's index finger pressed to a line on
the page, looking up from the page directly at the viewer with cool assessing
impatience, spine straight [C-PORTRAIT]
```

#### `C-07` 幼年继承人 · The Child Heir
**性格**：惊惶、被推上位、渴望躲藏
**外貌**：`a European boy of eight, small pale face, wide brown eyes, fine blond hair, an adult gold circlet slipped too low over his forehead nearly to the eyebrows, swamped in an oversized ermine-trimmed crimson wool mantle, its keyhole neck slit gaping at the throat over a cream silk tunic, a soft gilded belt, red hose and leather turnshoes`
```
[S] a European boy of eight seated on an adult sized carved wooden throne, small pale
face, wide frightened brown eyes, fine blond hair, an adult gold circlet slipped down
too low over his forehead nearly to the eyebrows, swamped in an oversized ermine trimmed
crimson mantle whose folds pool around him, both small hands gripping the throne's arms
with feet not reaching the floor, mouth slightly open, shoulders drawn up toward his
ears [C-PORTRAIT]
```

#### `C-08` 政治联姻的公主 · The Bride of Alliance
**性格**：认命、体面、内里崩溃
**外貌**：`a European princess of sixteen, round young face, grey eyes with reddened rims, loose unbound fair hair to the waist under a circlet of flowers, wearing a pale gold silk bridal gown with a wide round neckline edged in pearls and tight laced sleeves, a jewelled girdle at the hips, long skirts, cream hose and silk-covered turnshoes`
```
[S] a European princess of sixteen in bridal dress, round young face, reddened rims
around clear grey eyes, loose unbound fair hair falling past the waist crowned with a
circlet of fresh flowers, wearing a stiff pale gold silk gown with a jewelled girdle,
hands clasped tightly in front of her waist with the fingers white where they press,
chin lifted in careful practised composure, a single tear track drying on one cheek,
lips pressed into a courteous smile [C-PORTRAIT]
```

#### `C-09` 铁腕摄政太后 · The Iron Regent
**性格**：绝对权威、政治动物、不带感情
**外貌**：`a European dowager queen of fifty-five, severe handsome face, strong nose, heavy-lidded pale eyes, a widow's black barbette and veil under a narrow gold coronet, wearing a dark slate blue wool surcoat with fur trim and a high round collar over a black gown, a plain girdle, long skirts, black leather turnshoes, one heavy signet ring worn inward`
```
[S] a European dowager queen of fifty five, severe handsome face with a strong nose,
heavy lidded pale eyes, wearing a widow's black barbette and veil with a narrow gold
coronet over it, a dark slate blue surcoat with fur trim, both hands folded one over the
other at the waist in absolute stillness, no ornament except a heavy signet ring turned
inward on the palm, expression completely neutral, gaze level and evaluating, frontal
symmetrical composition suggesting authority [C-PORTRAIT]
```

#### `C-10` 流亡贵族 · The Exiled Lord
**性格**：怨毒、体面尽失、随时反扑
**外貌**：`a European nobleman of thirty-eight in decline, hollow unshaven cheeks, long unkempt dark hair, wearing a once-fine burgundy velvet houppelande now stained and frayed at the cuffs with its fur trim torn away, the high collar hanging open at the throat, a fine sword belt with an empty scabbard, patched dark hose and cracked leather riding boots`
```
[S] a European nobleman of thirty eight in decline, hollow unshaven cheeks, long unkempt
dark hair, wearing a once fine burgundy velvet houppelande now stained, frayed at the
cuffs and missing its fur trim, a fine sword belt with an empty scabbard, one hand
pulling the cloak closed across his chest, the other clenched into a fist at his side,
looking sideways out of frame with bitter narrowed eyes and a slight sneer, standing in
a hunched defensive posture [C-PORTRAIT]
```

### 2.2 宫廷与行政

#### `C-11` 大法官 · The Chancellor
**性格**：滴水不漏、真正的权力经纪人
**外貌**：`a European chancellor of forty-five, clean-shaven ascetic face, thin arched eyebrows, close-cropped greying hair with a tonsure, wearing sober dark slate wool scholar's robes with a fur-lined hood pushed back from a high collar, a narrow leather belt, long skirts over black hose and plain leather turnshoes, a wax seal matrix on a cord at his neck`
```
[S] a European chancellor of forty five, clean shaven ascetic face, thin arched
eyebrows, close cropped greying hair with a clerical tonsure, wearing sober dark slate
scholar's robes with a fur lined hood pushed back and a wax seal matrix hanging from a
cord at his neck, one hand tucked into the opposite sleeve, the other extended palm up
in a small precise explanatory gesture, faint patient smile, eyes attentive and
completely unreadable [C-PORTRAIT]
```

#### `C-12` 内府总管 · The Steward
**性格**：和善、事无巨细、绝不亏空
**外貌**：`a plump European household steward of fifty, ruddy round face, close-trimmed grey beard, thinning hair, wearing a practical dark green wool tunic with a keyhole neck slit closed by a drawstring, a broad leather belt carrying a heavy iron ring of a dozen keys, brown hose and sturdy leather ankle boots`
```
[S] a plump European household steward of fifty, ruddy cheerful face, close trimmed grey
beard, thinning hair, wearing a practical dark green wool tunic with a broad leather belt
from which hangs a heavy iron ring of a dozen keys, one hand resting on the keys, the
other holding a wooden tally stick notched with accounts, warm creased eyes, an open
friendly smile with a shrewd edge to it, slight forward bow of the head [C-PORTRAIT]
```

#### `C-13` 密探首领 · The Spymaster
**性格**：无表情、无姓名、无痕迹
**外貌**：`a European figure of indeterminate age, deliberately forgettable features, a straight mouth and plain jaw, a brown hooded wool cloak drawn up over the head so the upper face lies in deep shadow, beneath it a dark tunic with a plain round neck, a narrow leather belt, dark hose and soft leather turnshoes, no ornament`
```
[S] a European figure of indeterminate age in dark unremarkable clothing, a plain brown
hooded cloak drawn up so the upper face is in deep shadow with only a straight mouth and
jaw catching the light, no ornament of any kind, hands folded inside opposite sleeves at
waist height, body angled away from the viewer, entirely still, deliberately forgettable
features, the paper around the figure left more heavily hatched and dim than in any other
portrait [C-PORTRAIT]
```

#### `C-14` 宫廷医师 · The Court Physician
**性格**：博学、审慎、地位微妙
**外貌**：`a Jewish physician of sixty in a medieval European court, dignified narrow face, long white beard, deep-set eyes, wearing a pointed scholar's cap and a long dark blue wool robe with a high round collar fastened at the throat, a narrow leather belt at the waist, the skirts falling to dark leather turnshoes`
```
[S] a Jewish physician of sixty in a medieval European court, dignified narrow face,
long white beard, deep set thoughtful eyes, wearing a long belted dark blue robe with a
pointed scholar's cap, holding a clear glass uroscopy flask up toward the light at eye
level with one hand while the other hand steadies the elbow, head tilted, brow furrowed
in genuine diagnostic concentration, lips slightly pursed, treated with full dignity and
gravity [C-PORTRAIT]
```

#### `C-15` 御前书记 · The Royal Scribe
**性格**：近视、迂腐、记得每一件事
**外貌**：`a European monastic scribe of thirty-five, pale indoor complexion, permanently squinting watery eyes, ink stains on the fingers and a smudge on one cheek, a small tonsure, wearing an undyed wool habit with a wide keyhole neck opening and a knotted cord belt, the long skirts over plain leather turnshoes, no jewellery`
```
[S] a European monastic scribe of thirty five, pale indoor complexion, permanently
squinting watery eyes, ink stains on the fingers and one smudge on the cheek, a slightly
hunched scholar's posture, wearing an undyed wool habit, holding a trimmed quill poised
above an unrolled parchment strip he holds close to his face, mouth slightly open in
concentration, shoulders rounded from decades at a writing desk [C-PORTRAIT]
```

#### `C-16` 使节 · The Envoy
**性格**：油滑、多语、忠于出价最高者
**外貌**：`a European diplomat of forty, olive complexion, a neat pointed black beard, quick dark eyes, wearing a fur-trimmed chaperon hat and a well-cut travelling houppelande in verdigris green with a high collar laced at the throat, a narrow belt at the waist, dark hose and fine leather ankle boots, a gold chain of office across the chest`
```
[S] a European diplomat of forty, olive complexion, neat pointed black beard, quick
mobile dark eyes, wearing a well cut travelling houppelande in verdigris green with a
gold chain of office and a fur trimmed chaperon hat, caught mid bow with one hand sweeping
outward and down in an elaborate courtly flourish and the other pressed to his chest,
broad charming smile showing teeth, eyebrows raised in practised delight [C-PORTRAIT]
```

#### `C-17` 弄臣 · The Fool
**性格**：唯一敢说真话的人
**外貌**：`a European court fool of forty-five, sharp asymmetrical face, one shoulder higher than the other, thinning red hair, wearing a soft hood with two limp points over a faded parti-coloured tunic in ochre and moss green, small tarnished bells at the hem, a round neck slit laced with a cord, mismatched hose and worn leather turnshoes`
```
[S] a European court fool of forty five, sharp asymmetrical face, one shoulder visibly
higher than the other, thinning red hair, wearing a faded parti coloured tunic in ochre
and moss green with small tarnished bells at the hem and a soft hood with two limp points,
holding a carved marotte stick loosely in one hand, the other hand raised with the index
finger extended in a mocking lecture, mouth stretched in a wide grin while the eyes stay
flat, cold and entirely serious [C-PORTRAIT]
```

#### `C-18` 税吏 · The Tax Collector
**性格**：冷漠、精确、被所有人憎恨
**外貌**：`a European tax official of forty-eight, thin bloodless face, small close-set eyes, a downturned mouth, wearing a clerk's flat cap and plain well-maintained dark brown wool with a round neck closed by a small bronze brooch, a leather scrip purse on the belt, brown hose and neat leather ankle boots`
```
[S] a European tax official of forty eight, thin bloodless face, small close set eyes,
downturned mouth, wearing plain but well maintained dark brown wool with a clerk's flat
cap, a leather scrip purse on the belt, one hand holding a wooden tally stick and the
other making a mark on a wax tablet with a stylus, not looking at the viewer but down at
the tablet, expression of complete bureaucratic indifference [C-PORTRAIT]
```

#### `C-19` 王后侍女 · The Lady-in-Waiting
**性格**：谨慎、观察一切、消息的枢纽
**外貌**：`a European noblewoman of twenty-six, delicate features, alert dark eyes, hair coiled in netted cauls either side of the head under a light linen veil, wearing a modest but fine moss green wool gown with tight laced sleeves and a round neckline edged with narrow braid, a slim girdle, long skirts, cream hose and soft leather turnshoes`
```
[S] a European noblewoman of twenty six, delicate features, alert dark eyes, hair coiled
in netted cauls either side of the head under a light veil, wearing a modest but fine
moss green gown with tight sleeves, standing half turned as if she has just stopped
walking, one hand holding a small psalter closed against her body and the other lifting
the veil's edge slightly, glancing sidelong at the viewer with a carefully composed
expression that is one degree too watchful [C-PORTRAIT]
```

#### `C-20` 匠师建筑师 · The Master Builder
**性格**：固执、专业、只服从结构
**外貌**：`a European master mason of fifty-two, weathered square face, grey stubble, broad scarred hands with cracked nails, wearing an undyed linen coif tied under the chin and a sturdy brown wool tunic with rolled sleeves and a keyhole neck slit laced at the throat, a wide leather belt, brown hose and heavy leather ankle boots`
```
[S] a European master mason of fifty two, weathered square face, grey stubble, broad
scarred hands with cracked nails, wearing a practical undyed linen coif tied under the
chin and a sturdy brown wool tunic with rolled sleeves, holding a pair of iron dividers
open in one hand and a rolled vellum plan tucked under the opposite arm, looking at the
viewer with blunt appraising directness, one eyebrow slightly raised, unimpressed
[C-PORTRAIT]
```

#### `C-21` 宫廷大臣的女儿 · The Ambitious Daughter
**性格**：野心勃勃、二十岁、比父亲更懂时局
**外貌**：`a European young noblewoman of twenty, sharp clever face, amber eyes, auburn hair in two netted braids under a fine linen veil, wearing an elegantly cut slate blue gown with a wide round neckline and tight laced sleeves, a silver girdle, long skirts, pale hose and soft leather turnshoes, a small pendant at her throat`
```
[S] a European young noblewoman of twenty, sharp clever face, quick amber eyes, auburn
hair in two netted braids under a fine linen veil, wearing an elegantly cut slate blue
gown slightly above her station, one hand resting on a closed book of hours and the other
lightly touching the pendant at her throat, head tilted with a small private smile,
looking directly and confidently into the viewer's eyes without deference [C-PORTRAIT]
```

### 2.3 军事

#### `C-22` 老元帅 · The Old Marshal
**性格**：沉稳、经验、不再热血
**外貌**：`a European marshal of sixty-two, close-cropped white hair, heavy jaw, a network of old scars on the cheek and the bridge of the nose, steady grey eyes, wearing a mail hauberk and coif with a plain undecorated linen surcoat slit at the round neck, a simple sword belt with a sheathed longsword, mail chausses and leather riding boots`
```
[S] a European marshal of sixty two, close cropped white hair, heavy jaw, a network of
old scars on the cheek and the bridge of the nose, calm steady grey eyes, wearing a mail
hauberk with a plain undecorated surcoat and a simple sword belt, both hands resting one
over the other on the quillons of a sword grounded point down before him, absolutely
level frontal stance, expression composed and tired, the face of a man who has already
counted the dead [C-PORTRAIT]
```

#### `C-23` 少壮骑士 · The Young Banneret
**性格**：意气风发、荣誉至上、必将被现实教育
**外貌**：`a European knight of twenty-four, bright open face, wide blue eyes, fair hair damp at the temples from a helmet, wearing a mail hauberk with the coif pushed back to the shoulders over a fresh oxblood and gold heraldic surcoat with a neck slit laced at the throat, a gilded sword belt, mail chausses and gilt-spurred leather riding boots`
```
[S] a European knight of twenty four, bright open face flushed with excitement, blue
eyes wide, fair hair damp at the temples from a helmet, wearing a mail hauberk and coif
pushed back to the shoulders over a fresh oxblood and gold heraldic surcoat, one gauntleted
fist raised holding a small pennon on a short staff, the other hand on his hip, chest out
and chin up in an eager forward lean, grinning with unguarded enthusiasm [C-PORTRAIT]
```

#### `C-24` 老军士长 · The Grizzled Sergeant
**性格**：粗野、务实、真正带兵的人
**外貌**：`a European infantry sergeant of forty-five, broken nose, an upper tooth missing, heavy stubble, sun-darkened skin, wearing an iron kettle hat pushed back on the head, a padded linen gambeson with a mail collar over its laced round neck, a broad leather belt, dark hose and scuffed leather ankle boots`
```
[S] a European infantry sergeant of forty five, broken nose, missing an upper tooth,
heavy stubble, sun darkened skin, wearing a padded gambeson with a mail collar and an
iron kettle hat pushed back on the head, a bearded axe resting on one shoulder held by
the haft, the other hand jabbing a thick finger toward the viewer, mouth open bawling an
order, eyes hard and completely unimpressed [C-PORTRAIT]
```

#### `C-25` 长弓手 · The Longbowman
**性格**：沉默、耐心、致命
**外貌**：`a spare European archer of thirty, weathered narrow face, a sparse beard, an overdeveloped left shoulder and back from a lifetime at the bow, wearing a simple hood over an undyed linen shirt with rolled sleeves and a laced keyhole neck opening, a leather bracer on the left forearm, a narrow belt, brown hose and plain leather turnshoes`
```
[S] a lean European archer of thirty, weathered narrow face, sparse beard, an
overdeveloped left shoulder and back from a lifetime at the bow, wearing an undyed linen
shirt with rolled sleeves, a simple hood and a leather bracer on the left forearm,
drawing a great yew warbow to the ear with three fingers, the string distorting the cheek,
one eye squinted shut and the other locked on a distant target off frame, jaw clenched,
holding absolutely still [C-PORTRAIT]
```

#### `C-26` 弩手 · The Crossbowman
**性格**：技术工种、冷静、按流程做事
**外貌**：`a stocky European crossbowman of thirty-four, square unremarkable face, a short dark beard, wearing a mail collar over a quilted linen gambeson laced at the round neck, a large pavise shield slung on his back, a heavy belt with a spanning hook, dark hose and stout leather ankle boots`
```
[S] a stocky European crossbowman of thirty four, square unremarkable face, short dark
beard, wearing a mail collar over a quilted gambeson with a large pavise shield slung on
his back, bent forward with one foot in the stirrup of a crossbow spanning it with a belt
hook, both hands and the whole back straining at the cord, teeth gritted, eyes down on
the mechanism, a workmanlike expression of pure mechanical focus [C-PORTRAIT]
```

#### `C-27` 雇佣兵队长 · The Mercenary Captain
**性格**：贪婪、可靠到合同结束为止
**外貌**：`a European mercenary captain of thirty-eight, hard handsome face, dark hair tied back, a gold ring in one ear, wearing a jumble of fine mismatched equipment, an Italian mail shirt with one odd pauldron under a scavenged heraldic surcoat with the arms defaced and its neck slit laced askew, a sword belt, dark hose and worn riding boots`
```
[S] a European mercenary captain of thirty eight, hard handsome face, a gold ring in one
ear, dark hair tied back, a jumble of mismatched high quality equipment taken from
different dead men, a fine Italian mail shirt with a mismatched pauldron and a scavenged
heraldic surcoat with the arms deliberately defaced, one hand held out palm up rubbing
the fingertips together in the universal gesture for payment, the other resting on a
sword hilt, one eyebrow raised, a thin amused smile [C-PORTRAIT]
```

#### `C-28` 扈从少年 · The Squire
**性格**：崇拜、笨拙、还没杀过人
**外貌**：`a European squire of fifteen, round unfinished face, freckles across the nose, ears too large, unruly straw-coloured hair, cheeks smudged, wearing a plain oversized wool tunic belted twice to make it fit, its keyhole neck slit gaping at the throat, brown hose sagging at the knee and scuffed leather turnshoes, no jewellery`
```
[S] a European squire of fifteen, round unfinished face, freckles across the nose, ears
too large, unruly straw coloured hair, wearing a plain oversized wool tunic belted twice
to make it fit, kneeling and polishing a mail sleeve draped across his lap with a rag and
sand, glancing up at the viewer mid task with startled wide eyes and an open mouth, cheeks
smudged, an eager anxious to please expression [C-PORTRAIT]
```

#### `C-29` 攻城工程师 · The Siege Engineer
**性格**：数学脑、对人命不感兴趣
**外貌**：`a European siege engineer of forty, gaunt narrow face, wild greying hair escaping a linen coif, burn scars on the backs of both hands, wearing a filthy leather apron over an undyed wool tunic with a laced round neck, a belt of small tools at the waist, dark hose and heavy leather ankle boots`
```
[S] a European siege engineer of forty, gaunt intense face, wild greying hair escaping a
linen coif, burn scars on the backs of both hands, wearing a filthy leather apron over
undyed wool, holding up a small wooden scale model of a trebuchet counterweight in one
hand and pointing at its pivot with the other, staring at the model rather than the
viewer, eyebrows raised in the delighted absorbed expression of a man solving a problem
[C-PORTRAIT]
```

#### `C-30` 守城的女领主 · The Lady Holding the Walls
**性格**：临危受命、寸步不让（历史有据）
**外貌**：`a European noblewoman of thirty-five, strong-boned face streaked with soot, hair bound up tightly under a plain linen kerchief rather than a courtly veil, wearing a man's mail collar over the shoulders of a practical dark wool gown with a high laced neckline, the skirts hitched and belted up at the hip over dark hose and leather ankle boots`
```
[S] a European noblewoman of thirty five directing a castle's defence, strong boned
determined face streaked with soot, hair bound up tightly under a plain linen kerchief
rather than a courtly veil, wearing a practical dark gown with the skirts hitched and
belted up and a man's mail collar over the shoulders, one arm flung out pointing off
frame with the whole body committed to the gesture, the other hand fisted, shouting, eyes
blazing with absolute refusal [C-PORTRAIT]
```

#### `C-31` 残废老兵 · The Maimed Veteran
**性格**：被遗忘、酗酒、还在打上一场仗
**外貌**：`a European veteran of fifty, prematurely aged, deeply hollowed cheeks, a milky scar across the forehead, an empty left sleeve pinned up at the shoulder, wearing the rotted remains of a military gambeson under a patched beggar's cloak with a hood, the neck opening tied with a scrap of cord, frayed hose and broken leather turnshoes`
```
[S] a European veteran of fifty, prematurely aged, deeply hollowed cheeks, an empty left
sleeve pinned up at the shoulder, a milky scar across the forehead, wearing the rotted
remains of a military gambeson under a beggar's patched cloak, his single hand gripping a
crude crutch under the armpit, staring past the viewer at nothing with a flat thousand
yard gaze, mouth slightly open, entirely still [C-PORTRAIT]
```

#### `C-32` 骑兵队长 · The Cavalry Captain
**性格**：华丽、冲动、爱马胜过爱人
**外貌**：`a European cavalry captain of twenty-nine, sun-browned aquiline face, a well-kept moustache, long dark hair, wearing a mail hauberk under a well-fitted verdigris surcoat with a laced round neck, a fine sword belt, mail chausses, gilt spurs and tall leather riding boots`
```
[S] a European cavalry captain of twenty nine, sun browned aquiline face, a well kept
moustache, long dark hair, wearing a mail hauberk under a well fitted verdigris surcoat
with gilt spurs and a fine sword belt, one hand holding a coiled riding whip and a set of
reins, the other adjusting the strap of a great helm tucked under the arm, glancing back
over the shoulder at the viewer with a reckless confident grin, body already turning away
[C-PORTRAIT]
```

### 2.4 教会

#### `C-33` 主教 · The Bishop
**性格**：世俗、富有、政治动物
**外貌**：`a well-fed European bishop of fifty-five, smooth heavy-jowled face, small shrewd eyes, soft pink hands, wearing a tall white mitre and a richly embroidered silk cope clasped at the breast with a jewelled morse over a white linen alb with an embroidered round collar, a knotted cincture, red silk slippers, an enormous amethyst ring`
```
[S] a well fed European bishop of fifty five, smooth heavy jowled face, small shrewd
eyes, soft pink hands, wearing a rich embroidered cope over a white alb with a tall
mitre and holding a gilded crozier, an enormous amethyst ring on the blessing hand which
is raised in a perfunctory two fingered benediction, the other hand resting comfortably
on his own stomach, expression benign, complacent and entirely worldly [C-PORTRAIT]
```

#### `C-34` 苦修隐士 · The Ascetic Hermit
**性格**：狂热、真诚、危险
**外貌**：`an emaciated European hermit of sixty, skeletal face with every bone visible, a wild matted white beard to the chest, fever-bright eyes, sun-blackened skin, wearing only a rope-belted undyed linen robe, threadbare and ragged at the hem, its slit neck open at the collarbone, a knotted cord scourge at the waist, and bare dirty feet`
```
[S] an emaciated European hermit of sixty, skeletal face with every bone visible, a wild
matted white beard to the chest, burning fever bright eyes, sun blackened skin, wearing
only a rope belted sackcloth robe with bare feet and a knotted cord scourge at the waist,
one bony arm raised straight up with the index finger pointing at heaven, the other hand
clutching a rough wooden cross to his breast, mouth open mid prophecy, entirely
transported [C-PORTRAIT]
```

#### `C-35` 修道院长 · The Abbot
**性格**：务实、经营者、比多数领主更懂账
**外貌**：`a European Benedictine abbot of forty-eight, broad even face, clean-shaven with a neat tonsure, mild brown eyes, wearing a plain black wool habit with a hood lying flat over the shoulders and a round neck opening, a leather cincture at the waist, long skirts over black hose and plain leather turnshoes, a pectoral cross on a cord`
```
[S] a European Benedictine abbot of forty eight, calm broad face, clean shaven with a
neat tonsure, mild but shrewd brown eyes, wearing a plain black wool habit with a
pectoral cross and a simple staff, one hand holding a closed account roll against his
side and the other tucked into the opposite sleeve, standing squarely and comfortably,
faint pragmatic smile, the unhurried expression of a competent administrator [C-PORTRAIT]
```

#### `C-36` 女修道院长 · The Abbess
**性格**：严厉、博学、比主教更有原则
**外貌**：`a European abbess of fifty-seven, austere finely boned face, pale eyes, completely veiled in black over a white linen wimple drawn close around the face, wearing an undyed wool habit with a high round neck under a black scapular, a knotted cincture, long skirts over plain leather turnshoes, a plain silver ring of office`
```
[S] a European abbess of fifty seven, austere finely boned face, pale unwavering eyes,
completely veiled in black over a white wimple that frames the face tightly, wearing an
undyed habit with a plain silver ring of office, both hands resting on a closed illuminated
manuscript held at her waist, chin level, meeting the viewer's gaze with unblinking moral
authority and no warmth whatsoever [C-PORTRAIT]
```

#### `C-37` 托钵修士 · The Mendicant Friar
**性格**：亲民、走遍天下、真信
**外貌**：`a European friar of thirty-three, open weathered face, laugh lines around warm brown eyes, a rough tonsure grown out, dusty from the road, wearing a patched grey-brown wool habit with a pointed hood and a round neck opening, a rope cincture with a battered wooden bowl hanging from it, and bare dirty feet`
```
[S] a European friar of thirty three, open weathered kind face, dusty from the road,
laugh lines around warm brown eyes, a rough tonsure grown out, wearing a patched grey
brown habit with a rope cincture and bare dirty feet, a battered wooden bowl hanging from
the belt, both arms spread wide and low in an inclusive welcoming gesture mid sermon,
head tilted back slightly, mouth open in a broad genuine laugh [C-PORTRAIT]
```

#### `C-38` 异端审判官 · The Inquisitor
**性格**：冷静、有条理、毫无恶意——这才可怕
**外貌**：`a European Dominican inquisitor of forty-two, still symmetrical face, pale grey eyes, thin colourless lips, a precise tonsure, wearing a spotless black cappa with a hood over a white wool habit with a round neck opening, a leather cincture, the long skirts falling to black leather turnshoes, no ornament but a small plain cross`
```
[S] a European Dominican inquisitor of forty two, still symmetrical face, absolutely calm
pale grey eyes, thin colourless lips, a precise tonsure, wearing a spotless black cappa
over a white habit, one hand holding a small closed notebook and the other resting flat
on the table before him, sitting perfectly upright, head slightly tilted in polite
attentive listening, a faint courteous expression of mild patient interest, no anger at
all [C-PORTRAIT]
```

#### `C-39` 抄经僧 · The Illuminator
**性格**：眼睛快瞎了、活在颜料里
**外貌**：`an elderly European monastic illuminator of seventy, tiny stooped body, a milky cataract clouding one eye and the other squinted almost shut, a deeply wrinkled face, fingertips stained ultramarine and vermilion, a worn tonsure, wearing an undyed wool habit with a round neck and an ink-spotted scapular, a cord belt, plain leather turnshoes`
```
[S] an elderly European monastic illuminator of seventy, tiny stooped frame, milky
cataract clouding one eye, the other squinted almost shut, deeply wrinkled face, stained
fingertips in ultramarine and vermilion, wearing an undyed habit with an ink spotted
scapular, holding a fine squirrel hair brush a hand's width from his own eye while the
other hand steadies a small gold leafed initial on a vellum leaf, mouth pursed in intense
concentration [C-PORTRAIT]
```

#### `C-40` 随军教士 · The Crusade Preacher
**性格**：煽动、雄辩、送别人去死
**外貌**：`a European crusade preacher of forty-five, gaunt magnetic face, deep-set fanatical eyes, a shock of dark hair, wearing a plain undyed wool habit with a large red cloth cross sewn onto the breast, a wide keyhole neck slit at the throat, a rope cincture, the dusty skirts over plain leather turnshoes`
```
[S] a European crusade preacher of forty five, gaunt magnetic face, deep set fanatical
eyes, a shock of dark hair, wearing a coarse habit with a large red cloth cross sewn onto
the breast, both hands raised above the head gripping a plain wooden cross aloft, head
thrown back, mouth wide open in a full throated shout, cords standing out on the neck,
entire body straining upward [C-PORTRAIT]
```

### 2.5 平民与市井

#### `C-41` 铁匠 · The Blacksmith
**性格**：沉默、力量、村里真正被需要的人
**外貌**：`a European village blacksmith of forty, enormous corded forearms, soot-blackened skin, a singed beard, thick burn scars on the hands, wearing a heavy leather apron over a bare chest with its neck strap crossing one shoulder, rough linen braies at the hip, and plain leather ankle boots`
```
[S] a European village blacksmith of forty, enormous corded forearms, soot blackened
skin, sweat running through the grime, a singed beard, thick burn scars on the hands,
wearing a heavy leather apron over a bare chest and rough braies, gripping a hammer in
one fist and holding tongs with a glowing billet in the other, half turned toward the
viewer with a neutral incurious glance, unbothered [C-PORTRAIT]
```

#### `C-42` 行会长 · The Guild Master
**性格**：暴富、讲究排场、政治上很危险
**外貌**：`a prosperous European guild master of fifty-two, heavy well-fed face, a neatly forked grey beard, wearing an expensive fur-trimmed burgundy wool gown far finer than his birth entitles, its high collar closed at the throat, a broad tooled belt, dark hose and fine leather ankle boots, rings on four fingers and a guild chain of office over the shoulders`
```
[S] a prosperous European guild master of fifty two, heavy well fed face, neatly forked
grey beard, rings on four fingers, wearing an expensive fur trimmed burgundy gown far
finer than his birth entitles and a guild chain of office over it, one thumb hooked into
his belt and the other hand holding a small locked strongbox against his hip, chin
tucked, looking down his nose at the viewer with proprietary self satisfaction
[C-PORTRAIT]
```

#### `C-43` 客栈老板娘 · The Innkeeper
**性格**：泼辣、见多识广、知道所有八卦
**外貌**：`a European alewife of forty-four, broad ruddy face, strong bare forearms, greying brown hair escaping a linen kerchief, wearing a practical moss green kirtle with the sleeves pushed up and a round neck laced across the breast, a stained linen apron over the long skirts, wool hose and stout leather turnshoes`
```
[S] a European alewife of forty four, broad ruddy face, strong bare forearms, greying
brown hair escaping a linen kerchief, wearing a practical moss green kirtle with the
sleeves pushed up and a stained apron, one fist planted firmly on her hip and the other
hand holding a heavy ale jug by the handle, head cocked to one side, one eyebrow raised,
mouth twisted in a sceptical amused smirk, sizing the viewer up [C-PORTRAIT]
```

#### `C-44` 老农 · The Old Ploughman
**性格**：沉默、耐劳、见过三次饥荒
**外貌**：`a European peasant farmer of fifty-eight who looks seventy, deeply seamed sun-blackened face, white stubble, a permanently bent spine, enormous knotted arthritic hands, wearing a shapeless undyed wool tunic with a frayed hem and a plain slit neck tied with cord, a rope belt, bare legs wrapped in linen strips, and crude leather turnshoes`
```
[S] a European peasant farmer of fifty eight who looks seventy, deeply seamed sun
blackened face, white stubble, permanently bent spine, enormous knotted arthritic hands,
wearing a shapeless undyed wool tunic with the hem frayed, bare legs wrapped in cloth,
leaning both hands and his whole weight on the handles of a wooden plough, looking up
from under his brows with patient exhausted resignation [C-PORTRAIT]
```

#### `C-45` 磨坊主 · The Miller
**性格**：狡黠、缺斤短两、人人都恨他
**外貌**：`a European miller of forty-one, round dusty face, small darting eyes, everything from hair to eyebrows to clothing coated in a fine white film of flour, wearing a floury soft cap and a light-coloured wool tunic with a round neck slit tied at the throat, a leather belt, pale hose and dusty leather turnshoes`
```
[S] a European miller of forty one, round dusty face, everything from hair to eyebrows to
clothing coated in a fine white film of flour, small darting eyes, wearing a light coloured
wool tunic and a floury cap, one hand holding the neck of a grain sack and the other
resting on the beam of a balance scale with one finger pressing very slightly on the pan,
grinning ingratiatingly, eyes sliding away from the viewer [C-PORTRAIT]
```

#### `C-46` 草药婆与接生婆 · The Herbwife
**性格**：智慧、被需要也被恐惧
**外貌**：`a European village midwife of sixty-three, sharp knowing face, one clouded eye, deep lines, silver hair under a plain dark kerchief, wearing a worn undyed kirtle with a round neckline laced across the breast, a wide belt hung with small linen pouches, long skirts over dark hose and old leather turnshoes`
```
[S] a European village midwife of sixty three, sharp knowing face, one clouded eye, deep
lines, silver hair under a plain dark kerchief, wearing a worn undyed kirtle with a wide
belt hung with linen pouches, holding a bound bundle of dried herbs up to her nose with
one hand while the other hand's fingers rub a crushed leaf, eyes half closed in
assessment, mouth pursed, quietly formidable [C-PORTRAIT]
```

#### `C-47` 乞丐 · The Beggar
**性格**：绝望、隐形、社会的底
**外貌**：`a European beggar of indeterminate age between thirty and sixty, filthy matted hair and beard, one leg twisted and useless, sores visible on the shin, wearing layered rags tied with cord over a torn tunic with a gaping slit neck, a scrap of sacking as a hood, and both feet bound in rag strips`
```
[S] a European beggar of indeterminate age between thirty and sixty, filthy matted hair
and beard, one leg twisted and useless, sores visible on the shin, wearing layered rags
tied with cord and a scrap of sacking as a hood, kneeling and holding out a chipped wooden
bowl with both trembling hands, head bowed so the face is seen from above at an angle,
looking up with hopeless practised supplication [C-PORTRAIT]
```

#### `C-48` 小偷 · The Cutpurse
**性格**：敏捷、机会主义、随时准备跑
**外貌**：`a wiry European thief of twenty-three, thin quick face, sharp cheekbones, dark eyes, a knife scar through one eyebrow, wearing close-fitting dark nondescript clothing, a hood half up over a plain round-necked tunic laced at the throat, a narrow belt with a small sheathed blade, dark hose and soft leather shoes`
```
[S] a wiry European thief of twenty three, thin quick face, sharp cheekbones, dark eyes
already looking at the exit, a knife scar through one eyebrow, wearing close fitting dark
nondescript clothing with soft shoes and a hood half up, body coiled in a low crouch with
the weight on the balls of the feet, one hand palming a small blade close to the body, the
other reaching out sideways, glancing back over the shoulder, mouth in a tight nervous
grin [C-PORTRAIT]
```

#### `C-49` 游吟诗人 · The Minstrel
**性格**：表演型人格、消息贩子、不可信
**外貌**：`a European minstrel of twenty-seven, mobile youthful face, long dark curls, a theatrical arched eyebrow, wearing a feathered cap at a rakish angle over a jaunty parti-coloured tunic in ochre and verdigris with a laced round neck, a slim belt, mismatched hose and pointed leather ankle boots`
```
[S] a European minstrel of twenty seven, animated expressive face, long dark curls, a
theatrical arched eyebrow, wearing a jaunty parti coloured tunic in ochre and verdigris
with a feathered cap at a rakish angle, mid performance with a lute held high across the
body, one hand fretting the neck and the other caught in a downward strum, head thrown
back, mouth wide open singing, one leg forward, entire body in motion [C-PORTRAIT]
```

#### `C-50` 伦巴第银行家 · The Lombard Banker
**性格**：算计、跨国、比国王更懂钱
**外貌**：`a northern Italian banker of forty-six in medieval Europe, olive complexion, a neat short dark beard, heavy-lidded eyes, wearing a plain flat cap and a sober but extremely fine dark red wool gown with a fur collar clasped at the throat, a narrow belt with a purse, dark hose and fine leather turnshoes`
```
[S] a northern Italian banker of forty six in medieval Europe, olive complexion, neat
short dark beard, heavy lidded patient eyes, wearing a sober but extremely fine dark red
gown with a fur collar and a plain flat cap, seated behind a cloth covered counting board
with coins arranged in columns, one hand moving a counter across the board and the other
holding a bound ledger closed with a finger inside marking the page, looking up with a
polite immovable expression [C-PORTRAIT]
```

### 2.6 异邦与边缘

#### `C-51` 诺斯首领 · The Norse Jarl
**性格**：豪迈、暴力、重誓言
**外貌**：`a Scandinavian jarl of forty-two, weather-beaten face, a thick red-blond beard braided into two forks, hair shaved at the sides and long on top, wearing a fur mantle over a mail shirt and a blue wool tunic whose round neck is pinned by a penannular brooch, a wide belt, silver arm rings, dark trousers and leather ankle boots`
```
[S] a Scandinavian jarl of forty two, broad weather beaten face, pale blue eyes, a thick
red blond beard braided into two forks with small silver rings, hair shaved at the sides
and long on top, wearing a heavy fur mantle over a mail shirt with a large penannular
brooch and thick arm rings, both hands resting on the head of a long bearded axe grounded
before him, feet planted wide, head tilted back, roaring with laughter [C-PORTRAIT]
```

#### `C-52` 拜占庭将军 · The Byzantine Strategos
**性格**：文明、傲慢、视西欧人为蛮族
**外貌**：`a Byzantine general of fifty, olive-skinned face, an oiled square-cut black and grey beard, dark eyes, wearing a lamellar klibanion over a purple and gold silk tunic with a high embroidered collar, a jewelled pteruges skirt, a cloak fastened at the right shoulder by a gold fibula, a sword belt with a sheathed spathion and tall red leather boots`
```
[S] a Byzantine general of fifty, refined olive skinned face, an oiled square cut black
and grey beard, dark intelligent eyes, wearing a lamellar klibanion over a rich purple
and gold silk tunic with a jewelled pteruges skirt and a cloak fastened at the shoulder
with a gold fibula, one hand holding a rolled dispatch and the other resting on the hilt
of a spathion, standing in composed frontal stillness, expression of cultivated
condescension [C-PORTRAIT]
```

#### `C-53` 安达卢西亚学者 · The Andalusi Scholar
**性格**：沉静、渊博、被三方争抢
**外貌**：`an Andalusi scholar of fifty-five, thoughtful ascetic face, a closely trimmed grey beard, dark eyes, wearing an elegantly wound cream turban and a fine sober robe of cream linen and indigo silk whose high round neck is closed at the throat with a small cloth knot, a narrow sash at the waist, and soft leather slippers`
```
[S] an Andalusi scholar of fifty five, thoughtful ascetic face, closely trimmed grey
beard, calm dark eyes, wearing a fine but sober cream and indigo robe with an elegantly
wound turban, holding a brass astrolabe up at chest height with one hand while the other
turns the rete with a fingertip, head bent toward the instrument, absorbed, a faint smile
of intellectual pleasure, treated with full scholarly dignity [C-PORTRAIT]
```

#### `C-54` 草原弓骑 · The Steppe Horse-Archer
**性格**：风霜、寡言、来去如风
**外貌**：`a steppe nomad horse archer of thirty, broad high-cheekboned wind-burned face, a thin drooping moustache, narrow dark eyes, hair in a long braid under a fur-trimmed pointed cap, wearing a padded silk deel coat over lamellar, crossed and fastened high at the collar, a wide sash, a gorytos quiver at the hip, loose trousers and soft leather riding boots`
```
[S] a steppe nomad horse archer of thirty, broad high cheekboned wind burned face, thin
drooping moustache, narrow watchful dark eyes, hair in a long braid under a fur trimmed
pointed cap, wearing a padded silk over lamellar deel coat with a wide sash and a
gorytos quiver at the hip, holding a short recurve composite bow across the body with an
arrow nocked but undrawn, scanning the horizon off frame, expression completely flat and
alert [C-PORTRAIT]
```

#### `C-55` 黎凡特香料商 · The Levantine Spice Merchant
**性格**：世故、多语、和所有人做生意
**外貌**：`a Levantine merchant of forty-eight, warm brown skin, a full well-groomed dark beard going grey at the chin, crow's feet, wearing a wrapped headcloth and layered robes of fine linen and striped silk with a round neck opening slit at the throat, a wide sash at the waist, and soft leather slippers`
```
[S] a Levantine merchant of forty eight, warm brown skin, a full well groomed dark beard
going grey at the chin, crow's feet from smiling, wearing layered fine linen and striped
silk robes with a wrapped headcloth and a wide sash, holding a small open brass scale in
one hand with a pinch of saffron threads offered forward on the open palm of the other,
leaning in confidentially, eyebrows raised, a broad genuinely warm salesman's smile
[C-PORTRAIT]
```

---

## 2.6 本作角色 `K-`（2026-09-13 新增）

> §2 的 `C-01`~`C-55` 是**泛型原型**（年迈的国王、算计的王后…），而游戏里实际存在的是 `data/founding_council.csv` 和 `data/roles.csv` 里这 **21 个有名有姓的人**。头像格和档案栏要的是后者，所以这里一人一条。
>
> **每条都有 `**外貌**` 行**（只写长相和衣着，不写道具）——这是 `[C-BUST]` 和 `[C-FULL]` 两档的必要条件，没有它脚本会退回用带道具的主 prompt，效果差。
>
> **角色 id** 那一行把条目接回游戏：`data/cast_art.csv` 按它把 `K-` 编号映射到 `assets/portraits/<id>.png`。
>
> 年龄、性格、身份都取自那两张 CSV，不是编的——例如马尔文领主七十一岁且 `sickly`，所以外貌写的是佝偻、消瘦、穿着不合时令的厚皮袍。
>
> **不出现任何王国名**（架构约束 5）：外邦人物只写"来自西部丘陵"「来自东方宫廷」这类说法。

#### `K-01` 国王阿尔德里克 · King Aldric Valorin

**角色 id**：`you`

**外貌**：`a European king of forty, strong-jawed and clean-browed, short dark hair greying at the temples under a plain open gold circlet, a close-trimmed dark beard, wearing a deep blue wool mantle lined with miniver over a long embroidered tunic closed at the throat by a gold brooch, a gilded belt, dark hose and black leather turnshoes`

```
[S], a European king of forty in his prime, strong-jawed, short dark hair greying at the temples under a plain gold circlet, a close-trimmed beard, wearing a deep blue mantle over an embroidered tunic, one hand resting on the arm of a wooden throne, steady and unhurried, meeting the viewer's eye, [C-PORTRAIT]
```

#### `K-02` 大法官奥德温·里夫 · Chancellor Aldwin Reeve

**角色 id**：`char_chancellor`

**外貌**：`a European man of fifty-eight, narrow-faced and dry, thinning grey hair cut level at the ears, deep lines from nose to mouth, wearing a long dark green gown of fine wool with wide sleeves and a fur-trimmed collar over a black undertunic, a soft flat cap, and a plain leather belt`

```
[S], a European chancellor of fifty-eight, narrow-faced, thinning grey hair, wearing a long fur-collared green gown and a soft flat cap, hands folded one over the other at his waist, chin slightly lowered, watching with an appraising half-smile, [C-PORTRAIT]
```

#### `K-03` 元帅布兰特 · Ser Brandt of Harrow

**角色 id**：`char_marshal`

**外貌**：`a European knight of forty-five, heavy-browed and weather-beaten, short iron-grey hair and a cropped beard, an old white scar through one eyebrow, wearing a padded arming coat of oxblood wool over a mail hauberk, a broad belt with a sword hanger, mail chausses and leather boots`

```
[S], a European marshal of forty-five, weather-beaten, iron-grey cropped hair and beard, a scar through one eyebrow, in a padded oxblood arming coat over mail, one fist on his belt, shoulders squared, jaw set hard, [C-PORTRAIT]
```

#### `K-04` 内府总管米蕾拉 · Mirella of the Weighhouse

**角色 id**：`char_steward`

**外貌**：`a European woman of forty-one, square-faced and plain, brown hair drawn back entirely under a white linen coif and wimple, level brows, wearing a practical slate-grey wool gown with tight buttoned sleeves and a broad woven girdle hung with a ring of keys, dark hose and flat leather shoes`

```
[S], a European stewardess of forty-one, square-faced, hair under a white linen coif, in a slate-grey gown with a girdle of keys, arms folded, looking straight out with a flat unimpressed expression, [C-PORTRAIT]
```

#### `K-05` 密探首领奎尔 · Quill

**角色 id**：`char_spymaster`

**外貌**：`a wiry European of thirty-seven, sharp-featured and sallow, lank black hair to the jaw, restless dark eyes set close, wearing an unremarkable brown hooded cloak over a close-fitting grey doublet with no badge or ornament of any kind, dark hose and soft quiet shoes`

```
[S], a wiry European spymaster of thirty-seven, sharp-featured, lank black hair, in a plain brown hooded cloak, half turned away with the hood pushed back, glancing sideways at the viewer without moving his head, [C-PORTRAIT]
```

#### `K-06` 随军教士奥多神父 · Father Odo

**角色 id**：`char_chaplain`

**外貌**：`a European priest of sixty-three, round-faced and softened by age, a fringe of white hair around a shaved tonsure, heavy pouched eyes, wearing a plain undyed woollen habit belted with a knotted cord, a wooden cross on a leather thong, and worn sandals`

```
[S], a European priest of sixty-three, round-faced, white fringe around a tonsure, in a plain belted woollen habit with a wooden cross, both hands closed around the cross at his chest, eyes lowered, calm and tired, [C-PORTRAIT]
```

#### `K-07` 王后维多利亚 · Queen Victoria

**角色 id**：`char_queen`

**外貌**：`a European queen of thirty-six, oval-faced with a high plucked forehead, dark steady eyes, hair entirely concealed under a white linen wimple and barbette with a narrow gold fillet, wearing a close-fitted deep red gown with tight buttoned sleeves, a woven girdle, long skirts and black leather turnshoes`

```
[S], a European queen of thirty-six, composed, hair under a white wimble and gold fillet, in a close-fitted deep red gown, standing very still with her hands lightly clasped, a faint knowing half-smile that does not reach her eyes, [C-PORTRAIT]
```

#### `K-08` 公主诺拉 · Princess Nora O-kala

**角色 id**：`char_princess`

**外貌**：`a young European woman of nineteen with warm brown skin, strong straight brows and close-cropped black curls uncovered, an athletic build, wearing a short riding cotehardie of dark green wool cut for movement over hose and calf boots, a narrow belt, and no jewellery but a small gold ring`

```
[S], a young woman of nineteen with warm brown skin and cropped black curls, athletic, in a short green riding cotehardie and boots, weight on one leg with her chin up, restless and openly impatient, [C-PORTRAIT]
```

#### `K-09` 托马斯公爵 · Duke Tomas Valorin

**角色 id**：`char_duke_tomas`

**外貌**：`a European nobleman of forty-four, handsome and sharp-boned, dark hair worn to the collar and swept back, a thin moustache, wearing a fashionable parti-coloured cotehardie in black and gold with dagged sleeves, a jewelled belt slung low, parti-coloured hose and pointed leather ankle boots`

```
[S], a European duke of forty-four, handsome and sharp-boned, dark swept-back hair, in a black-and-gold parti-coloured cotehardie with a jewelled belt, leaning back at ease with one eyebrow raised, entirely pleased with himself, [C-PORTRAIT]
```

#### `K-10` 伊索尔德夫人 · Lady Ysolde Valorin

**角色 id**：`char_lady_ysolde`

**外貌**：`a European woman of twenty-seven, pretty and soft-featured, fair hair dressed in two coiled braids over the ears under a fine gold net, wearing a pale rose gown of light wool with long trailing sleeves, a jewelled girdle high at the waist, and soft embroidered shoes`

```
[S], a European lady of twenty-seven, pretty and soft-featured, fair hair in coiled braids under a gold net, in a pale rose gown with trailing sleeves, one hand at her throat, smiling for an audience that is not the viewer, [C-PORTRAIT]
```

#### `K-11` 海尔上尉 · Captain Hale Fenwick

**角色 id**：`char_captain_hale`

**外貌**：`a European soldier of fifty-two, broad and thickset, close-cropped grey hair, a broken nose and a jaw of stubble, wearing a plain leather brigandine over a russet tunic, a soldier's wide belt, sturdy hose and heavy marching boots`

```
[S], a European captain of fifty-two, broad and thickset, cropped grey hair and a broken nose, in a plain leather brigandine, standing squarely at rest with his hands behind his back, patient and entirely unimpressed, [C-PORTRAIT]
```

#### `K-12` 科琳娜夫人 · Lady Corina Ashvale

**角色 id**：`char_lady_corina`

**外貌**：`a European noblewoman of forty-three, fine-boned with a long neck, dark hair smoothed back under a crespine of gold net and a sheer veil, hooded watchful eyes, wearing a deep violet gown with a fitted bodice and a fur-lined surcoat, a slender jewelled girdle`

```
[S], a European noblewoman of forty-three, fine-boned, dark hair under a gold crespine and veil, in a deep violet gown and fur-lined surcoat, standing three-quarters away and looking back over one shoulder, measuring the viewer, [C-PORTRAIT]
```

#### `K-13` 埃德加领主 · Lord Edgar Harrow

**角色 id**：`char_lord_edgar`

**外貌**：`a European lord of forty-nine, square and ruddy, thick sandy hair going grey and a full short beard, wearing a heavy russet houppelande with wide fur-lined sleeves over a dark tunic, a broad worked belt, and stout riding boots`

```
[S], a European lord of forty-nine, square and ruddy, sandy greying hair and a short beard, in a russet fur-lined houppelande, feet planted wide and both thumbs hooked in his belt, blunt and unbothered, [C-PORTRAIT]
```

#### `K-14` 马尔文领主 · Lord Malvern

**角色 id**：`char_lord_malvern`

**外貌**：`a European lord of seventy-one, gaunt and stooped, sparse white hair over a spotted scalp, sunken eyes and hollow cheeks, wearing a long dark brown furred gown far too heavy for the season, a soft cap, and thick lined shoes`

```
[S], a European lord of seventy-one, gaunt and stooped, sparse white hair, in a long furred gown too heavy for the season, one hand closed on the head of a walking stick, upright by effort, lucid and unhurried, [C-PORTRAIT]
```

#### `K-15` 赤足者卡西安 · Cassian the Barefoot

**角色 id**：`char_prophet_cassian`

**外貌**：`a European man of thirty-three, lean and sun-blackened, wild dark hair to the shoulders and an untrimmed beard, burning deep-set eyes, wearing a single coarse undyed woollen robe belted with rope, sleeves pushed back over thin forearms, and bare dirty feet`

```
[S], a European preacher of thirty-three, lean and sun-blackened, wild dark hair and beard, in a rope-belted undyed robe and bare feet, one arm half raised mid-sentence, eyes fixed on something past the viewer, [C-PORTRAIT]
```

#### `K-16` 战酋奥斯里克 · Warchief Osric

**角色 id**：`char_king_osric`

**外貌**：`a European warlord of forty-seven from the western hills, huge and thick-necked, long red-brown hair in plaits and a heavy braided beard, pale scarred skin, wearing a wolfskin mantle over a mail shirt, iron arm rings, rough woollen trews and cross-gartered boots`

```
[S], a European warlord of forty-seven, huge and thick-necked, plaited red-brown hair and a braided beard, in a wolfskin mantle over mail with iron arm rings, filling the frame, chin down and staring flatly out, [C-PORTRAIT]
```

#### `K-17` 使节佩特拉 · Envoy Petra Kolev

**角色 id**：`char_envoy_petra`

**外貌**：`a European woman of thirty-eight from the eastern courts, olive-skinned and neat-featured, black hair coiled and pinned under a small embroidered cap, wearing a high-collared travelling gown of dark teal wool with fitted sleeves, a short fur-lined mantle clasped at the shoulder, and riding boots`

```
[S], a European envoy of thirty-eight, olive-skinned and neat, black coiled hair under an embroidered cap, in a dark teal travelling gown and fur-lined mantle, standing straight with her hands quiet in front of her, pleasant and telling nothing, [C-PORTRAIT]
```

#### `K-18` 王后伊莎博 · Queen Isabeau

**角色 id**：`char_queen_isabeau`

**外貌**：`a European queen of forty-five, handsome and hard-eyed, fair hair drawn severely back under an elaborate horned headdress with a sheer veil, wearing a stiff cloth-of-gold gown with a long trailing train and a jewelled collar at the shoulders`

```
[S], a European queen of forty-five, handsome and hard-eyed, fair hair under a horned headdress and veil, in a stiff cloth-of-gold gown and jewelled collar, drawn to full height with her hands clasped low, looking down at the viewer, [C-PORTRAIT]
```

#### `K-19` 皇帝康斯坦斯 · Emperor Constans

**角色 id**：`char_emperor`

**外貌**：`a European young man of twenty-four, pale and slight with a soft unformed face, fine light hair to the jaw and no beard, wearing an enormous jewelled imperial mantle of purple and gold that overwhelms his shoulders, a heavy closed crown, and embroidered shoes`

```
[S], a European emperor of twenty-four, pale and slight with a soft unformed face, in an enormous jewelled purple mantle and a heavy crown that overwhelm him, sitting very upright, uncertain and trying not to show it, [C-PORTRAIT]
```

#### `K-20` 乐师科尔文 · Master Corvin Lute

**角色 id**：`char_bard_corvin`

**外貌**：`a European man of thirty-one, lively and good-looking, chestnut hair curling to the collar, a neat moustache, wearing a bright particoloured doublet in blue and saffron with slashed sleeves, a soft feathered cap at an angle, tight hose and pointed shoes`

```
[S], a European minstrel of thirty-one, lively and good-looking, curling chestnut hair and a feathered cap at an angle, in a blue-and-saffron particoloured doublet, mid-flourish with one hand open, grinning straight at the viewer, [C-PORTRAIT]
```

#### `K-21` 行会长苔莎 · Guildmaster Tessa Marden

**角色 id**：`char_guildmaster_tessa`

**外貌**：`a European woman of thirty-nine, broad-shouldered and capable, brown hair plaited and pinned under a simple white linen cap, strong hands, wearing a sober dark brown gown of good cloth with a fur-trimmed collar, a guild badge at the breast, and a heavy purse on a plain girdle`

```
[S], a European guildmaster of thirty-nine, broad-shouldered and capable, plaited brown hair under a linen cap, in a sober fur-collared brown gown with a guild badge, one hand resting on her purse, direct and businesslike, [C-PORTRAIT]
```

---

## 3. 表情与姿态差分 `E-` / `P-`

> **⚠️ 关键规则：表情差分绝对不要重新生成整张图。**
>
> 正确做法：拿 `C-xx` 已定稿的立绘作为输入，用**图生图 / 局部重绘**（Qwen-Image-Edit、Flux Kontext、Nano Banana），只重绘面部区域，锁定 seed。这样服装、发型、配饰、光照逐像素不变，只有表情变。
>
> 用法：`<C-xx 定稿图>` + `change only the facial expression to:` + `[E-xx 片段]` + `keep the clothing, hair, hands, lighting and background exactly unchanged`

### 3.1 表情片段 `E-`（16 种，覆盖大战略常用情绪状态）

| ID | 情绪 | 片段 |
|---|---|---|
| `E-01` | 中性 · Neutral | `a calm neutral expression, relaxed mouth, level gaze, eyebrows at rest` |
| `E-02` | 满意 · Content | `a small closed-mouth smile, eyes slightly crinkled at the corners, eyebrows relaxed and slightly raised` |
| `E-03` | 大喜 · Joyful | `a broad open-mouthed laugh, head tilted back slightly, deep smile lines, eyes nearly closed with mirth` |
| `E-04` | 震怒 · Wrathful | `teeth bared, brows slammed down and drawn together, nostrils flared, cords standing out on the neck, face flushed dark` |
| `E-05` | 冷怒 · Cold Anger | `jaw muscles visibly clenched, lips pressed into a bloodless line, eyes narrowed and utterly still, no other movement` |
| `E-06` | 悲痛 · Grief | `eyes reddened and wet, inner eyebrows pulled sharply up and together, mouth turned down and trembling at the corners` |
| `E-07` | 恐惧 · Fear | `eyes wide with white showing above the iris, eyebrows raised and drawn together, mouth slightly open, face drained of colour` |
| `E-08` | 多疑 · Suspicion | `one eyebrow raised and the other lowered, eyes narrowed and tracking sideways, mouth pulled slightly to one side` |
| `E-09` | 轻蔑 · Contempt | `one corner of the mouth pulled up and back in a unilateral sneer, eyelids lowered, chin lifted, looking down the nose` |
| `E-10` | 阴谋 · Scheming | `a slow closed-mouth smile that does not reach the eyes, eyes half-lidded and fixed, head tilted very slightly forward` |
| `E-11` | 疲惫 · Exhaustion | `heavy drooping eyelids, dark hollows beneath the eyes, slack unfocused gaze, mouth slightly parted, facial muscles gone loose` |
| `E-12` | 痛苦 · Pain | `eyes screwed shut, deep vertical furrow between the brows, lips drawn back from the teeth, sweat on the forehead` |
| `E-13` | 狂热 · Zeal | `eyes wide and fixed on something distant and above, pupils bright, mouth open mid-word, entire face lit from within` |
| `E-14` | 羞愧 · Shame | `eyes cast down and away from the viewer, head lowered, cheeks flushed, mouth pulled tight and small` |
| `E-15` | 惊讶 · Shock | `eyebrows shot high, forehead creased in horizontal lines, eyes fully round, jaw dropped open` |
| `E-16` | 决意 · Resolve | `eyes locked directly forward and unblinking, brows level and low, mouth firm and closed, chin set, whole face still` |

### 3.2 姿态片段 `P-`（12 种，用于生成同一角色的不同全身立绘）

> 姿态差分**需要重新生成**（不是局部重绘），所以务必：锁定角色 LoRA + 锁定 `[S]` + 只替换姿态描述。

| ID | 姿态 | 片段 |
|---|---|---|
| `P-01` | 端坐王座 | `seated upright on a carved wooden throne, both hands on the armrests, feet planted, frontal symmetrical` |
| `P-02` | 站立宣告 | `standing with weight on the back foot, one arm extended forward palm down in a declarative gesture` |
| `P-03` | 俯身指图 | `leaning forward over a table, one hand flat on a spread map and the other pointing at a location on it` |
| `P-04` | 单膝跪地 | `kneeling on one knee, head bowed, one hand over the heart and the other resting on a grounded sword hilt` |
| `P-05` | 背手踱步 | `walking in three-quarter profile, both hands clasped behind the back, head down in thought` |
| `P-06` | 骑马 | `mounted on a caparisoned destrier in three-quarter view, reins in the left hand, right hand raised` |
| `P-07` | 交谈倾听 | `standing in three-quarter view, head tilted toward an unseen speaker off-frame, one hand cupping the elbow of the other arm` |
| `P-08` | 拔剑起势 | `feet apart in a fighting stance, sword half-drawn from the scabbard, body coiled and turned` |
| `P-09` | 依墙沉思 | `leaning one shoulder against a stone wall, arms folded across the chest, ankles crossed` |
| `P-10` | 伏案书写 | `seated hunched at a sloped writing desk, quill in hand touching the parchment, other hand steadying the sheet` |
| `P-11` | 举杯 | `standing and raising a horn cup high with one arm, the other arm flung wide, body open` |
| `P-12` | 被押解 | `standing with the wrists bound in front, shoulders pulled back, head up in defiance or down in defeat` |

### 3.3 差分矩阵建议

主要角色（王室、可玩角色）出全套；次要角色只出必要的：

| 角色等级 | 表情 | 姿态 | 单角色图数 |
|---|---|---|---|
| 主要（约 12 人） | 全 16 种 | 6 种 | 22 |
| 次要（约 20 人） | E-01/02/04/06/08/16 共 6 种 | 2 种 | 8 |
| 背景（约 23 人） | E-01 + E-02 | 1 种 | 2 |

**人物类总图数约 12×22 + 20×8 + 23×2 = 470 张。** 这是排期时要按的数。

---

## 4. 世界地图底图 `M-`

> **⚠️ 最重要的一条规则：AI 不画地理形状。**
>
> 海岸线、河流、山脉位置、疆界必须来自真实 GIS 数据（Natural Earth / GEBCO / SRTM）。流程是：**QGIS 渲染出结构素图（线稿 + 高程灰度）→ 作为 ControlNet(lineart + depth) 输入 → 用下面的 prompt 上画风。**
>
> 直接拿这些 prompt 让 AI 凭空生成地图，会得到漂亮但地理上完全虚构的东西。

### 4.1 分 zoom 层级的底图画风

#### `M-01` z0–z2 世界层底图 · World Plate
**用途**：主界面最外层，整个已知世界 | **画幅**：`[C-MAP]`
```
[S] an antique world map plate on aged cream laid paper, landmasses rendered in pale
ochre and moss green with delicate stippled coastlines, oceans in a very light wash of
slate blue with fine parallel hatching only near the shores, no political borders, no
place names, no text of any kind, extremely restrained detail suitable for viewing at
great distance, the paper's laid lines and a faint foxing of age visible throughout,
generous empty margins [C-MAP]
```

#### `M-02` z3–z4 大陆层底图 · Continental Plate
```
[S] a continental scale antique map plate on cream laid paper, land in layered ochre and
moss green with major mountain ranges indicated by soft grey brown hachure strokes, major
rivers as thin sepia lines, coastlines finely stippled, sea in pale slate blue with
sparse hatching, no borders, no text, no settlements, medium detail density, even
weighting across the whole sheet [C-MAP]
```

#### `M-03` z5–z6 区域层底图 · Regional Plate
```
[S] a regional antique map plate on cream laid paper, hill and mountain relief drawn in
fine brown hachure strokes following the slope direction, forests indicated by small
repeated moss green tree symbols, marshes by short horizontal dashes, rivers as tapering
sepia lines widening downstream, cultivated land in pale ochre stipple, no text, no
political borders, high detail density, uniform across the sheet [C-MAP]
```

#### `M-04` z7–z8 省级底图 · Provincial Plate
```
[S] a provincial scale antique map plate on cream laid paper, individual wooded copses
and field boundaries visible as fine pencil lines, roads as double dashed sepia lines,
streams and fords picked out, relief in delicate cross hatched shading, hedgerows and
strip fields suggested by directional hatching, no text, no icons, very high detail
density, the drawing tighter and finer than at lower zoom [C-MAP]
```

#### `M-05` z9–z11 城域底图 · Environs Plate
```
[S] a town environs map plate on cream laid paper drawn at high magnification, individual
field strips, orchards as dotted grids, mill leats, bridges, tracks and hedge lines all
rendered in fine sepia pencil, subtle ochre and moss green colour washes over the fields,
building footprints as small solid umber blocks, no text, no labels, extremely fine line
work [C-MAP]
```

#### `M-06` z12+ 街区底图 · Street Plate
```
[S] a medieval town street plan on cream laid paper, individual burgage plots and timber
framed building footprints drawn as fine outlined blocks in umber, street surfaces left
as bare paper, the town wall and gates picked out in heavier line, wells courtyards and
gardens indicated, a river with a stone bridge, no text, no labels, architectural
draughtsman precision [C-MAP]
```

### 4.2 底图叠加层

#### `M-07` 海洋层 · Ocean Overlay
```
[S] a seamless antique cartographic ocean surface on cream laid paper, very pale slate
blue wash, fine parallel horizontal hatching lines increasing in density toward the top
of the frame, occasional faint stipple, no waves, no ships, no monsters, no text, entirely
uniform and tileable, extremely low visual weight so overlaid symbols read clearly
[C-TILE]
```

#### `M-08` 高程晕滃层 · Hachure Relief Overlay
```
[S] an antique cartographic hillshade layer, brown grey hachure strokes radiating down
the fall line of slopes, dense on steep faces and absent on flat ground, drawn in raw
umber pencil on transparent ground with no base colour, no outlines, no text, designed to
be multiplied over a coloured basemap [C-MAP]
```

#### `M-09` 政治疆界层 · Border Overlay
```
[S] antique cartographic political boundary lines, a fine solid sepia line paired with a
soft feathered band of translucent colour bleeding inward from the line, in the manner of
hand tinted eighteenth century atlas borders, drawn in colored pencil with visible
granular edge, on transparent ground, no fill, no text [C-MAP]
```

#### `M-10` 战争迷雾层 · Fog of War Overlay
```
[S] an unexplored region treatment for an antique map, the paper left blank cream with
only the faintest ghost of a graphite underdrawing, edges dissolving into loose
unfinished pencil strokes and open paper, as if the cartographer stopped drawing, soft
irregular boundary, no hard edge, no text [C-MAP]
```

#### `M-11` 做旧层 · Aging Overlay
```
[S] an aged paper damage layer, soft brown foxing spots, a faint tea coloured stain
blooming from one corner, two horizontal fold creases with slight abrasion along them,
a scatter of tiny wormholes, fine paper fibre texture, on transparent ground, no
imagery, no text, subtle and low contrast, designed as a multiply overlay [C-TILE]
```

#### `M-12` 图廓装饰边 · Map Border Frame
```
[S] an antique map plate border frame, a double ruled sepia line enclosing a narrow band
of graduated latitude ticks, with restrained foliate corner ornaments in raw umber and a
faint verdigris accent, drawn in colored pencil, the centre entirely empty cream paper,
no text, no numerals, symmetrical [C-MAP]
```

#### `M-13` 罗盘玫瑰 · Compass Rose
```
[S] an antique compass rose drawn in colored pencil, a sixteen point star with alternating
raw umber and pale ochre limbs, a fine circular graduated ring around it, the north point
marked with a slender fleur de lis, subtle granular pencil shading giving each limb
volume, isolated on transparent background, no text, no letters [C-ICON]
```

#### `M-14` 比例尺 · Scale Bar
```
[S] an antique map scale bar drawn in colored pencil, a long narrow rectangle divided
into alternating filled and open segments in raw umber, with a fine bracketing line above
and small tick divisions, slight hand drawn irregularity, isolated on transparent
background, no numerals, no text [C-ICON]
```

---

## 5. 地形平铺贴图 `T-`

> **用途**：这 20 张贴图是让 1600 万张地图瓦片变得可行的关键。由代码按 GIS 的地表分类数据（landcover raster）程序化拼贴，而不是逐张生成瓦片。
>
> **每种务必出 4–6 个变体**（改 seed 不改 prompt），拼贴时随机取用，否则大面积区域会出现肉眼可见的重复图案。
>
> 所有 prompt 结尾统一用 `[C-TILE]`。

| ID | 地形 | Prompt 主体（前接 `[S]`，后接 `[C-TILE]`） |
|---|---|---|
| `T-01` | 温带阔叶林 | `a seamless top-down forest canopy texture of rounded deciduous crowns in layered moss green and yellow ochre, each crown drawn with short curved pencil strokes and a soft umber shadow on its lower right, dense and evenly distributed` |
| `T-02` | 针叶林 | `a seamless top-down coniferous forest texture of small dark spired crowns in deep moss green and slate, sharper angular pencil strokes, tighter spacing, cool toned` |
| `T-03` | 疏林与灌木 | `a seamless top-down scattered woodland texture, isolated small tree crowns and low scrub clumps in muted moss green over bare ochre ground showing between them, roughly forty percent coverage` |
| `T-04` | 耕地条田 | `a seamless top-down medieval open field texture, long narrow strip fields in alternating pale ochre and warm sienna running in a consistent direction, separated by fine umber baulk lines, gentle ridge and furrow hatching` |
| `T-05` | 草地牧场 | `a seamless top-down pasture texture in soft moss green with a fine short vertical stipple, occasional darker tufts and a few thin hedge lines, low contrast and calm` |
| `T-06` | 荒原与石楠 | `a seamless top-down moorland texture, mottled dull olive and dusty purple grey stipple over exposed umber ground, scattered small rock outcrops, sparse and bleak` |
| `T-07` | 丘陵 | `a seamless top-down rolling hill texture, soft rounded landforms shown by directional brown hachure on the slopes with pale ochre on the crests, no hard outlines, gentle relief` |
| `T-08` | 山地 | `a seamless top-down mountain texture, sharp ridgelines and steep faces in dense raw umber hachure with pale grey blue on the shaded flanks and bare cream on the sunlit crests, angular and dramatic` |
| `T-09` | 高山雪线 | `a seamless top-down alpine texture, bare grey blue rock with white snowfields left as unmarked cream paper following the gullies, sparse hard hatching, very high contrast` |
| `T-10` | 沼泽湿地 | `a seamless top-down marshland texture, short horizontal dash marks in dull green grey over pale slate blue standing water, irregular reed clumps, soft blurred edges` |
| `T-11` | 干草原 | `a seamless top-down steppe texture, vast flat expanse of pale straw ochre with a very fine even horizontal stipple, almost no features, a few faint dry watercourse lines` |
| `T-12` | 沙漠 | `a seamless top-down desert texture, warm pale sienna and cream dune forms indicated by long soft parallel curves with delicate shadow hatching on one side of each ridge, no vegetation` |
| `T-13` | 苔原 | `a seamless top-down tundra texture, muted grey green and dusty ochre mottling with irregular pale patches of lichen and small dark thaw ponds, flat and cold toned` |
| `T-14` | 葡萄园 | `a seamless top-down vineyard texture, tight regular rows of small dark green dots on pale sienna terraced ground, strong directional order, warm toned` |
| `T-15` | 橄榄与果园 | `a seamless top-down orchard texture, a regular grid of evenly spaced small rounded grey green crowns each with a tiny umber trunk shadow, over dry ochre ground` |
| `T-16` | 浅海 | `a seamless top-down shallow sea texture, pale verdigris tinted water with fine horizontal hatching and faint stippled sandbanks showing through, very low contrast` |
| `T-17` | 深海 | `a seamless top-down deep ocean texture, uniform pale slate blue with fine even parallel horizontal hatching and nothing else, extremely low visual weight` |
| `T-18` | 河流与湖泊 | `a seamless top-down inland water texture, pale slate blue with a soft darker edge band and a few fine current lines, calm and flat` |
| `T-19` | 冰川与浮冰 | `a seamless top-down ice texture, near white cream paper with fine angular pale blue crevasse lines and sparse grey blue shadow, hard edged and sparse` |
| `T-20` | 焦土废墟 | `a seamless top-down burned land texture, blackened grey umber ground with irregular charcoal patches, a few skeletal dark stumps, ash grey stipple, desaturated and grim` |

---

## 6. 地图元素与图标 `I-`

> **通用规则**：全部使用 `[C-ICON]`（正交俯视 3/4 角、无背景、无地面、无投影到地面的影子）。
>
> **必须做的一步**：每个图标出 **3 档尺寸版本**（大 256px / 中 128px / 小 64px），**分别生成而不是缩放**。缩放会把彩铅颗粒糊掉，且小尺寸下细节会变成噪点。小尺寸版本的 prompt 追加 `extremely simplified, bold readable silhouette, minimal internal detail`。
>
> 势力归属靠**代码染色**（把图标的中性色相做 hue-shift），不要为每个势力单独生成图标。

### 6.1 聚落分级

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `I-01` | 农庄（1 级） | `a single medieval timber-framed longhouse with a thatched roof and a small fenced croft beside it, one thin smoke line, drawn small and modest` |
| `I-02` | 村庄（2 级） | `a cluster of six medieval thatched cottages around a green with a small stone church tower and a well, surrounded by a low hedge` |
| `I-03` | 集镇（3 级） | `a compact medieval market town of twenty timber-framed and stone buildings along two crossing streets, a market cross at the junction, a church with a spire, a wooden palisade` |
| `I-04` | 城市（4 级） | `a walled medieval city with crenellated stone curtain walls, a gatehouse with twin drum towers, dense tiled rooftops, a cathedral rising above them, a river gate` |
| `I-05` | 大都会（5 级） | `a great medieval metropolis with a double ring of walls, many towers and spires, a cathedral and a citadel, a bridge lined with houses crossing a broad river, dense and sprawling` |

### 6.2 防御工事分级

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `I-06` | 土木寨堡 | `a motte-and-bailey castle, an earthen mound topped by a wooden tower with a palisade and a ditched bailey below, raw and primitive` |
| `I-07` | 石造主塔 | `a square Norman stone keep with pilaster buttresses, small round-arched windows and a forebuilding, standing within a low curtain wall` |
| `I-08` | 同心城堡 | `a concentric stone castle with a high inner ward, round corner towers, a twin-towered gatehouse, a wet moat and a drawbridge` |
| `I-09` | 边境要塞 | `a stark frontier fortress of rough grey stone on a rock spur, a single massive tower, sloped talus base, minimal windows, purely military` |
| `I-10` | 城墙塔楼段 | `a short section of crenellated medieval curtain wall with one round mural tower and an arrow loop, drawn as a modular repeatable piece` |
| `I-11` | 瞭望烽火台 | `a slender stone watchtower on a rocky knoll with an iron fire basket on its roof and a small lean-to at its base` |

### 6.3 宗教建筑

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `I-12` | 乡村教堂 | `a small Romanesque parish church of pale stone with a squat square tower, round-arched windows and a lych gate` |
| `I-13` | 大教堂 | `a great Gothic cathedral with twin west towers, flying buttresses, a rose window and a soaring nave roof, the dominant structure of its skyline` |
| `I-14` | 修道院 | `a Cistercian monastery complex, a plain aisleless church, a square cloister with an arcaded walk, a chapter house, barns and a fishpond` |
| `I-15` | 朝圣圣地 | `a pilgrimage shrine church with a reliquary chapel, an ambulatory, a stone cross in the forecourt and worn pilgrim paths converging on it` |
| `I-16` | 军事修会堡 | `a military order commandery, a fortified stone compound combining a round chapel, a hall and a defensive wall, austere and functional` |
| `I-17` | 清真寺 / 异邦圣所 | `a medieval mosque with a low domed prayer hall, a slender square minaret and an arcaded courtyard with a central fountain, pale stone` |

### 6.4 经济与生产

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `I-18` | 集市 | `a medieval market square with striped awning stalls, a stone market cross, trestle tables and scattered barrels and crates` |
| `I-19` | 港口 | `a medieval harbour with a stone quay, a timber crane, two moored cogs with furled sails and stacked cargo barrels` |
| `I-20` | 水磨坊 | `a timber-framed watermill astride a leat with a large undershot wheel, a millpond and a sluice gate` |
| `I-21` | 风磨坊 | `a medieval post mill on a timber trestle with four latticed sails and a tail pole, standing on a low mound` |
| `I-22` | 矿井 | `a medieval mine head, a timbered adit mouth in a hillside with a windlass, spoil heaps and a wooden ore cart on rails` |
| `I-23` | 采石场 | `an open stone quarry with stepped cut faces, a treadwheel crane, stacked dressed blocks and a ramp` |
| `I-24` | 铁匠工坊 | `a village smithy, an open-fronted timber shed with a stone forge chimney, an anvil, a slack tub and a rack of tools` |
| `I-25` | 造船厂 | `a medieval shipyard slipway with a half-built clinker hull on stocks, timber stacks, a sawpit and a tar barrel` |
| `I-26` | 商栈货仓 | `a merchant staple warehouse, a tall stone-and-timber building with a hoist beam and loading door in the gable, bales stacked outside` |
| `I-27` | 盐田 | `coastal medieval salt pans, a grid of shallow evaporation ponds with low earth banks, wooden rakes and small white salt heaps` |

### 6.5 学术与特殊地点

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `I-28` | 大学 | `a medieval university college, a stone quadrangle with an arcaded walk, a hall with a high oriel window and a small library range` |
| `I-29` | 医院 / 麻风院 | `a medieval hospital, a long stone infirmary hall with a chapel at one end, an arcaded porch and a walled herb garden` |
| `I-30` | 罗马遗迹 | `overgrown Roman ruins, a broken aqueduct arcade and a fallen column drum half buried in grass, weathered pale stone, ivy` |
| `I-31` | 古战场 | `an old battlefield site, a low grassed burial mound with a weathered stone marker cross and a few rusted spear points in the turf` |
| `I-32` | 异教圣所 | `a pre-Christian sacred site, a standing stone circle on open moorland with carved spirals, worn and lichen-covered` |
| `I-33` | 温泉浴场 | `a medieval bathhouse over a hot spring, a low stone vaulted building with steam rising from an open pool and a timber changing hut` |

### 6.6 地形特征点

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `I-34` | 石桥 | `a medieval stone bridge of three pointed arches with cutwaters and a small chapel on the central pier` |
| `I-35` | 渡口 | `a river ford, a shallow gravelled crossing with worn approach tracks on both banks and a marker post` |
| `I-36` | 渡船 | `a medieval river ferry, a flat timber punt on a rope guided across the water, with a landing stage` |
| `I-37` | 山口 | `a mountain pass, a narrow track winding between two steep rock shoulders with a small stone refuge hut and a wayside cross` |
| `I-38` | 灯塔 | `a medieval lighthouse, a squat round stone tower on a headland with an open fire platform at the top` |
| `I-39` | 驿站客栈 | `a roadside medieval inn, a timber-framed building with a projecting upper floor, a hanging painted sign bracket with a blank board, a stable and a horse trough` |

### 6.8 地图标记（兴趣点，2026-09-11 新增）

> 地图包里的标记类型比 6.5/6.6 多（Azgaar 的 markers：encounters、brigands、pirates、statues、necropolises、caves、volcanoes、waterfalls、circuses、jousts、fairs…）。具体类型到图标的映射在 `data/marker_art.csv`。
>
> **没有怪物、地牢和冒险小队**（owner 裁定 2026-09-12：这是中世纪写实硬核战略）。Azgaar 默认会生成 `hill-monsters` / `sea-monsters` / `lake-monsters` / `dungeons` / `party`，全部不收——`data/marker_types.csv` 列出这个世界承认的类型，导入器丢掉其余的，**所以重新导出地图也带不回来**（2026-09-12 重跑导入器验证：只有 markers.csv 变了，少 8 行，其余表逐字节不变）。同理删掉了 §6.9 的 `D-22 海怪`，`D-16` 从「童话城堡」改成一座真实石堡，`I-43` 从「插着骷髅的匪巢」改成一座普通的匪徒营地。

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `I-43` | 匪患之地 | `an outlaw camp in the woods, a lean-to of branches against a rock outcrop, a dead campfire, a plundered cart tipped on its side and a rope strung between two trees` |
| `I-44` | 纪念碑与墓地 | `a weathered stone monument, a tall carved cross on a stepped plinth beside a small walled graveyard with leaning headstones and a yew tree` |
| `I-45` | 自然奇观 | `a natural wonder, a waterfall dropping from a rock ledge into a clear pool beside a cave mouth, mist, ferns and wet stone` |
| `I-46` | 集会与庆典 | `a fairground gathering, striped canvas tents and pennants around a tilting field with a wooden grandstand and a small crowd` |

### 6.7 资源图标

> 这一组用于资源栏和贸易界面，画幅仍是 `[C-ICON]`，但**主体是静物而不是建筑**，追加片段：`arranged as a small still-life group on bare paper, no container beyond what is described`

| ID | 资源 | Prompt 主体 |
|---|---|---|
| `I-40` | 谷物 | `a bound sheaf of golden wheat with a few loose ears fallen beside it and a wooden measuring scoop` |
| `I-41` | 葡萄酒 | `an oak wine barrel on its side with an iron-banded rim, a wooden bung and a dark bunch of grapes on the vine leaf beside it` |
| `I-42` | 羊毛 | `a tied fleece of raw cream wool with a pair of iron shears and a wooden drop spindle wound with yarn` |

> **界面维度图标**（2026-09-13，owner：顶栏资源和国家卡的各维度全部改用图标，文字退到悬停提示）：同一画幅、同一风格核、同一静物片段，所以一整套读起来是一家的。对应关系在 `data/resource_icons.csv` 的 `texture` 列（谷物直接用 `I-40`）。图标在界面里只有 20 设计像素，主体要**一眼可辨的大剪影**，配件不超过两三样。

| ID | 维度 | Prompt 主体 |
|---|---|---|
| `I-47` | 金库 · Treasury | `a small open leather purse spilling a heap of gold coins, three coins stacked beside it, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-48` | 人口 · People | `three small painted wooden figures of townsfolk standing side by side, a man in a hood, a woman in a white wimple and a child, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-49` | 军队 · Host | `a round wooden shield with an iron boss and two swords crossed behind it, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-50` | 军队素质 · Drill | `a bright sword laid across a grey whetstone with a folded rag and a small oil flask, freshly sharpened, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-51` | 动荡 · Unrest | `a burning torch and a wooden pitchfork crossed, a few sparks rising, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-52` | 正统 · Legitimacy | `a golden crown resting on a red velvet cushion with gold tassels, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-53` | 民心 · Contentment | `a round loaf of brown bread on a wooden board beside a wooden mug of ale and a wedge of cheese, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-54` | 教会 · Church | `a gilded processional cross on a short staff beside a small bronze hand bell, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-55` | 步兵 · Infantry | `a kettle helmet, a spear and a kite shield leaning together, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-56` | 弓手 · Archers | `a strung longbow beside a leather quiver of grey-fletched arrows, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-57` | 骑兵 · Cavalry | `a warhorse's head in a leather bridle with a steel chamfron, a lance with a pennant beside it, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-58` | 炮兵 · Artillery | `a small bronze bombard cannon on a wooden carriage with three stone balls stacked beside it, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-59` | 舰队 · Fleet | `a small medieval cog ship with one square sail and a pennant, seen from the side, on a short curl of water, arranged as a small still-life group on bare paper, no container beyond what is described` |
| `I-60` | 城镇 · Towns | `a cluster of three timber-framed town houses with steep red tile roofs behind a low stone wall` |
| `I-61` | 乡村 · Country | `a thatched farmhouse beside a small field of ripe wheat and an apple tree` |

> **补充资源图标**（同样格式，按需生成）：`铁 — a stack of rough iron blooms and a pair of tongs`；`盐 — a heaped cone of white salt on a coarse cloth with a wooden scoop`；`银 — a small pile of hammered silver pennies and an ingot`；`木材 — a stacked cord of split oak logs with a felling axe`；`战马 — a coiled leather bridle, a curb bit and a horseshoe`；`香料 — three small open sacks of saffron, pepper and cinnamon bark with a brass scale pan`；`毛皮 — a rolled bundle of marten and fox pelts tied with cord`；`蜂蜜与蜡 — a woven straw skep, a honeycomb section and a beeswax candle`。

### 6.9 手绘地图装饰件 `D-`（2026-09-12 新增）

> **这一组不属于 `I-`，风格核也不一样。** owner 2026-09-12 定的方向：地图上的符号走单色深褐的手绘故事书地图风，人物和事件插图继续用 §1.1 的 v2 彩铅风。所以 `D-` 用 `STYLE_CORE_map_sepia.txt`（附录 A 第二段）配 `NEGATIVE_map_sepia.txt`（附录 B 第二段），画幅用 `[C-MAPMARK]`（平侧立面、纯白底），不是 `[C-ICON]` 的正交俯视 3/4 角。
>
> **纯白底是硬要求**：白纸经 `assets/flux/sepia_alpha_template.json` 的亮度转 alpha 变成透明，褐色笔触的毛边天然保留半透明。生成时底一旦带羊皮纸色或画框，去底就会连着底一起留下。
>
> **自然件要另配一份负面词**（2026-09-12 踩到的坑）：第一批 `D-01`~`D-18` 跑出来，针叶林里长出教堂、山脚杵着城堡、连沼泽和岩堆都带塔楼。原因在风格核自己——它原来写着 `steep exaggerated roofs, tall slender towers and oversized doorways`，那是为聚落写的，套到树和山上模型就把被要求画的塔楼塞进来。风格核里那句已经换成不指定题材的措辞，另外给自然件配了 `NEGATIVE_map_sepia_natural.txt`（在通用负面词前面加禁掉一切建筑），跑 `D-01`~`D-12`、`D-17`~`D-26` 时用 `--negative-file NEGATIVE_map_sepia_natural.txt`；聚落五档 `D-27`~`D-31` 和 `D-13`~`D-16` 本来就是建筑，用通用那份。
>
> `D-` 收散布装饰件和聚落五档。桥（`I-34`）、灯塔（`I-38`）、风磨坊（`I-21`）、教堂（`I-12`）这类单体不重复立条目——同一条 `I-` 主体换 `--style-file STYLE_CORE_map_sepia.txt --canvas C-MAPMARK` 重出一张就够用。但**聚落五档不能这么复用**，见下表前的说明。

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `D-01` | 针叶树（单株） | `a single conifer drawn as a map symbol, a narrow spire of stacked drooping branch tiers with a short bare trunk, tiny and simple` |
| `D-02` | 针叶林丛 | `a clump of five conifers of staggered heights standing close together as one map symbol, their crowns overlapping, a suggestion of undergrowth at the base` |
| `D-03` | 阔叶树（单株） | `a single broadleaf tree drawn as a map symbol, a stout short trunk splitting into two limbs under a wide billowing crown of scalloped foliage clumps, a few exposed roots` |
| `D-04` | 阔叶树丛 | `a clump of three broadleaf trees of different sizes standing as one map symbol, their rounded crowns overlapping into a single billowing mass` |
| `D-05` | 枯树 | `a dead tree drawn as a map symbol, a gnarled leafless trunk with a hollow knot and two clawing bare branches, bark peeling, sinister and twisted` |
| `D-06` | 灌丛与荆棘 | `a low thicket of bramble and scrub drawn as a map symbol, a tangled rounded mass of thin arching stems with small leaves and a few thorns` |
| `D-07` | 丘陵鼓包 | `a pair of low rolling hills drawn as a map symbol, two overlapping smooth humps with a soft crease between them, hatching only along the lower slope` |
| `D-08` | 单峰山 | `a single mountain peak drawn as a map symbol, a steep angular cone with a notched ridge line and a shaded facet on one flank, hatched cliffs` |
| `D-09` | 连绵山脉 | `a short mountain range drawn as one map symbol, four angular peaks of descending height overlapping in a row, each with one shaded flank` |
| `D-10` | 耕地条田格 | `a block of ploughed strip fields drawn as a map symbol, a rectangle divided into narrow furrowed strips by fine parallel lines, a low hedge along one edge` |
| `D-11` | 葡萄园架 | `a vineyard plot drawn as a map symbol, rows of low staked vines on a rectangle of sloping ground, each row a line of small tied bundles` |
| `D-12` | 路牌指路柱 | `a wooden wayside signpost drawn as a map symbol, a leaning post carrying two blank pointing boards, a stone at its foot and a tuft of grass` |
| `D-13` | 独立农舍 | `a lone thatched cottage drawn as a map symbol, a small steep-roofed cob building with a low door, one shuttered window and a thin line of smoke` |
| `D-14` | 木架市镇屋 | `a timber-framed town house drawn as a map symbol, a tall narrow building with an exposed frame, a jettied upper floor, a steep tiled gable facing front and small shuttered windows` |
| `D-15` | 双塔城门楼 | `a town gatehouse drawn as a map symbol, a crenellated stone block pierced by a tall arched gateway, flanked by two round towers with conical caps and a short stub of wall on each side` |
| `D-16` | 城堡 | `a stone castle drawn as a map symbol, a square keep behind a crenellated curtain wall with round corner towers under conical roofs and a gatehouse, a pennant on the keep, plainly built and defensible` |
| `D-17` | 岩露头 | `a rocky outcrop drawn as a map symbol, three angular boulders stacked on a low shelf of fractured stone with hatched shadow faces` |
| `D-18` | 沼泽草丛 | `a patch of marsh drawn as a map symbol, tufts of tall reed and sedge rising from short horizontal water dashes with one standing pool` |
| `D-19` | 大帆船 | `a three-masted medieval carrack drawn as a map symbol, a high stern castle, bellied square sails, a pennant streaming from the mainmast and a small bow wave` |
| `D-20` | 小帆船 | `a single-masted cog drawn as a map symbol, a broad clinker hull with a steering oar, one square sail on a yard and a small pennant` |
| `D-21` | 沉船残骸 | `a shipwreck drawn as a map symbol, a broken hull half sunk at an angle with a snapped mast and torn rigging trailing in the water, exposed ribs` |
| `D-22` | 鲸 | `a whale drawn as a map symbol, a great smooth-backed whale breaching among short water dashes with a spout above it, the way a real animal is drawn on an old chart — no monster, no tentacles, no teeth` |
| `D-23` | 礁石小岛 | `a tiny rocky islet drawn as a map symbol, a low mound of stone ringed by short water dashes with two leaning palms and a spar of driftwood` |
| `D-24` | 棕榈树 | `a single palm drawn as a map symbol, a slender curving ringed trunk under a crown of long drooping fronds, a small tuft of grass at its foot` |
| `D-25` | 高脚屋 | `a stilt hut drawn as a map symbol, a small thatched shack raised on timber legs above the shallows with a plank walkway and a beached dugout canoe below` |
| `D-26` | 海面波纹记号 | `a small group of cartographic wave marks, three short shallow open curves like flattened birds scattered at different angles, the standard filler mark of an old sea chart, extremely simple` |

**聚落五档**（2026-09-12 补）：第一批试图证明 `I-01`~`I-05` 的主体压不住立体感——那五条是当年为 `[C-ICON]` 的俯视 3/4 角写的，本身就在描述一个立体沙盘，换画幅也改不掉。所以这里按平侧立面另写五条，`data/settlement_art.csv` 的五档对应到这里，不再复用 `I-`。

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `D-27` | 农庄（1 级） | `a single thatched longhouse drawn as a map symbol, one steep straw roof over a low cob wall, a small plank door, a leaning wattle fence and a haystack beside it, one thin curl of smoke` |
| `D-28` | 村庄（2 级） | `a village drawn as one map symbol, four small thatched cottages of staggered heights standing in a row, a squat church tower with a short spire rising behind them, a low hedge running along the front` |
| `D-29` | 集镇（3 级） | `a market town drawn as one map symbol, a row of timber-framed houses with exposed frames, jettied upper floors and steep tiled gables, a stone market cross before them, a church spire behind, a stub of wooden palisade at each end` |
| `D-30` | 城市（4 级） | `a walled city drawn as one map symbol, a crenellated stone wall across the front pierced by an arched gate between two round towers, steep tiled roofs crowded behind the wall and a cathedral with twin towers rising above them` |
| `D-31` | 大都会（5 级） | `a great city drawn as one map symbol, a long crenellated wall with many towers across the front, behind it a dense rank of steep roofs and slender spires and one tall cathedral, a bridge lined with houses running out to one side` |
| `D-32` | 庄园十档 1（≤3 千人） | `a tiny holding: a single thatched cottage with one narrow strip field of furrows beside it, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-33` | 庄园十档 2 | `a small holding: a thatched farmhouse and a lean-to barn, two strip fields in front, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-34` | 庄园十档 3 | `a farmstead: house, barn and a wattle-fenced yard with a haystack, three strip fields in a row before it, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-35` | 庄园十档 4 | `a small manor: a stone house with a thatched barn and a round dovecote, four strip fields and a haystack, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-36` | 庄园十档 5 | `a manor: a two-storey stone manor house in a walled yard with barn and stable, a block of strip fields to each side, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-37` | 庄园十档 6 | `a manor with tenants: a stone hall with a gatehouse, two barns, three thatched tenant cottages and an orchard of small round trees, wide strip fields, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-38` | 庄园十档 7 | `a large manor: a hall with a chapel beside it, a water mill by a pond, a tithe barn, a row of tenant cottages, broad strip fields, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-39` | 庄园十档 8 | `a great manor: a hall with a corner tower, a chapel with a small spire, a mill, a tithe barn, dovecote, six tenant cottages, strip fields and an orchard, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-40` | 庄园十档 9 | `a fortified manor: a hall behind a low crenellated wall with a gatehouse and a corner tower, chapel, mill, barns, a hamlet of cottages, extensive strip fields, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-41` | 庄园十档 10（≥3 万人） | `a great manor estate: a moated hall with two towers, a chapel with a spire, a mill, a tithe barn, a dovecote, a hamlet of many cottages, wide strip fields bounded by hedges, drawn as one map symbol in flat side elevation, the fields as furrowed rectangles of fine parallel lines lying flat in the foreground, everything joined into one compact group with nothing scattered` |
| `D-42` | 首都（3D 试验） | `a medieval capital city as one game piece: a great walled city on a low green hill, crenellated pale stone walls with many round towers, an arched gate between twin towers, dense steep red-tiled and slate roofs crowded inside, a cathedral with twin spires and a royal castle keep with banners on the crest, a small river with a stone bridge at the foot of the wall, the whole city isolated as a single object on a pure white background` |
| `D-43` | 庄园·粮田·小 | `a small grain holding: a thatched cottage beside one narrow strip field of furrows, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-44` | 庄园·粮田·中 | `a grain manor: a stone farmhouse with a barn, a windmill on a low mound, three strip fields of furrows in front, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-45` | 庄园·粮田·大 | `a great grain estate: a manor hall with a tithe barn, two windmills, a hamlet of thatched cottages, wide strip fields of furrows bounded by hedges, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-46` | 庄园·牧牛·小 | `a small cattle holding: a thatched cottage with a wattle-fenced paddock holding two cows, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-47` | 庄园·牧牛·中 | `a cattle manor: a stone farmhouse with a long byre, a fenced pasture with a small herd of cattle and a water trough, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-48` | 庄园·牧牛·大 | `a great cattle estate: a manor hall with two long byres, wide fenced pastures with herds of cattle, a hamlet of cottages and a haystack yard, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-49` | 庄园·牧羊·小 | `a small sheep holding: a stone cottage with a dry-stone sheepfold holding a few sheep, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-50` | 庄园·牧羊·中 | `a sheep manor: a farmhouse with a shearing shed, a large stone-walled fold, a flock of sheep grazing on a low slope, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-51` | 庄园·牧羊·大 | `a great sheep estate: a manor hall with a wool barn and shearing sheds, many stone-walled folds, flocks across the slopes, a hamlet of cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-52` | 庄园·林场·小 | `a small timber holding: a woodcutter's cottage with a stack of cut logs and a few felled trunks, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-53` | 庄园·林场·中 | `a timber manor: a farmhouse with a saw-pit shed, stacked timber, a coppice of broadleaf trees behind, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-54` | 庄园·林场·大 | `a great timber estate: a manor hall with long timber sheds and a saw-pit, great stacks of logs, a woodland behind, a hamlet of cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-55` | 庄园·蜂场·小 | `a small bee holding: a thatched cottage with three straw bee skeps on a bench, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-56` | 庄园·蜂场·中 | `a honey manor: a farmhouse with a row of straw bee skeps under a lean-to, a small orchard of round trees, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-57` | 庄园·蜂场·大 | `a great honey estate: a manor hall with long benches of bee skeps under sheds, a large orchard of round trees, a hamlet of cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-58` | 庄园·葡萄园·小 | `a small wine holding: a stone cottage beside two rows of staked vines on a slope, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-59` | 庄园·葡萄园·中 | `a wine manor: a stone farmhouse with a wine-press shed and barrels, terraces of staked vines on the slope, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-60` | 庄园·葡萄园·大 | `a great wine estate: a manor hall with a large press house and rows of barrels, wide terraced vineyards of staked vines, a hamlet of cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-61` | 庄园·椰枣·小 | `a small date holding: a flat-roofed mud-brick cottage with three date palms, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-62` | 庄园·椰枣·中 | `a date manor: a flat-roofed mud-brick house with a walled courtyard, a grove of date palms along an irrigation channel, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-63` | 庄园·椰枣·大 | `a great date estate: a large flat-roofed mud-brick house with towers, a wide grove of date palms along irrigation channels, a cluster of mud-brick cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-64` | 庄园·皮毛·小 | `a small trapping holding: a log cabin with a frame of stretched pelts drying beside it, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-65` | 庄园·皮毛·中 | `a fur manor: a timber lodge with drying frames of stretched pelts and a store hut, a dark conifer wood behind, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-66` | 庄园·皮毛·大 | `a great fur estate: a timber hall with long rows of drying frames of pelts, store houses, a cluster of log cabins, a conifer forest behind, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-67` | 庄园·渔业·小 | `a small fishing holding: a thatched cottage on the shore with one boat drawn up and a net drying on a rack, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-68` | 庄园·渔业·中 | `a fishing manor: a stone house with a wooden jetty, three boats drawn up, racks of drying nets and fish, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-69` | 庄园·渔业·大 | `a great fishing estate: a manor house on the shore with a long stone quay, many boats, smokehouses and drying racks, a row of fishermen's cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-70` | 庄园·盐田·小 | `a small salt holding: a cottage beside two rectangular salt pans of shallow water, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-71` | 庄园·盐田·中 | `a salt manor: a stone house with a salt store, a grid of rectangular salt pans, a wooden rake and heaps of salt, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-72` | 庄园·盐田·大 | `a great salt estate: a manor house with large salt stores, wide grids of rectangular salt pans, white heaps of salt, a row of workers' cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-73` | 庄园·采石·小 | `a small quarry holding: a cottage beside a small quarry face with a few cut stone blocks, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-74` | 庄园·采石·中 | `a stone manor: a stone house with a masons' shed, a quarry face with a wooden hoist and stacked cut blocks, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-75` | 庄园·采石·大 | `a great quarry estate: a manor house with masons' halls, a wide quarry face with hoists and cranes, great stacks of cut blocks, a hamlet of cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-76` | 庄园·铁矿·小 | `a small mine holding: a cottage beside a timbered mine adit into a hillside with an ore cart, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-77` | 庄园·铁矿·中 | `an iron manor: a stone house with a bloomery furnace giving smoke, a timbered mine adit into the hill, ore carts and heaps of ore, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |
| `D-78` | 庄园·铁矿·大 | `a great iron estate: a manor house with several bloomery furnaces giving smoke, mine adits into the hill, ore carts on rails, heaps of ore, a hamlet of cottages, drawn as one map symbol in flat side elevation, everything joined into one compact group with nothing scattered, the ground of the holding lying flat in the foreground` |

> **产业庄园 `D-43`~`D-78`**（owner 2026-09-14）：庄园图例按 **产业 × 规模** 分——十二种主业（`data/manor_focus.csv`）各三档（小/中/大，人口三分位），一张里画齐主宅和该产业的作业场（粮田带风车、牧场带牛羊、林场带锯坑、渔村带码头、盐田带盐池、矿场带炉与坑道……）。地图上所有庄园图例**同一尺寸、居中**（owner：不再有大有小），人口升档或主业改换，图例随之换张。取代了 `D-32`~`D-41` 的十档纯粮田版。

> **3D 试验 `D-42`**（owner 2026-09-13）：同一个首都主体配五套 3D 风格核 `STYLE_CORE_3d_lowpoly / 3d_painted / 3d_diorama / 3d_watercolour / 3d_toon`（负面词 `NEGATIVE_3d.txt`，画幅 `[C-ICON]`），owner 从中挑一种作为聚落 3D 化的方向。
>
> **庄园十档 `D-32`~`D-41`**（owner 2026-09-13）：MANORS 视图里每座没有城镇的庄园按人口挂一张——主宅与农田画在一起，从一间茅屋一块条田到带护城河的大宅与整片田地。拼零件（房子、田块各自散布）被 owner 否掉：凌乱且不合理。用地图符号风格核和 `[C-MAPMARK]`，条田作为前景的平铺矩形一起画进符号里。

### 6.10 经济产物图标 `G-`（2026-09-13 新增）

> **为什么另立一章**：地图包的 `economy/production.csv` 把产出记到每个市镇，按省汇总后，**199 个省里共有 38 种主导货物**——这就是 ECONOMY 视图要画的那批图标，数量由数据定，不是拍脑袋定的。`data/goods_art.csv` 把 `good_code` 映射到这里的 `G-` 编号。
>
> **风格**：和 `D-` 同一套——`STYLE_CORE_map_sepia.txt` + `[C-MAPMARK]`，出完**去色成灰度**，由引擎按货物类别染色（`data/goods_palette.csv`）。所以主体只写形状和质感，不写颜色。
>
> **主体是静物**：`I-` 是建筑和地点，这里是**物**。追加片段由画幅负责，条目本身只描述摆在一起的几样东西。

| ID | 货物 | Prompt 主体 |
|---|---|---|
| `G-01` | 腌制食品 | `a salted side of bacon hanging from a hook beside a crock of preserved meat sealed with cloth and cord` |
| `G-02` | 布匹 | `a bolt of woven woollen cloth partly unrolled, with a pair of shears laid across it` |
| `G-03` | 玻璃 | `three blown glass vessels of uneven thickness, a flask, a beaker and a small bottle, standing together` |
| `G-04` | 谷物 | `a bound sheaf of wheat with a few loose ears fallen beside it and a wooden measuring scoop` |
| `G-05` | 烈酒 | `a squat earthenware jar with a wooden stopper beside a small copper still with a coiled pipe` |
| `G-06` | 靴 | `a pair of turned leather ankle boots side by side, worn at the heel, with a cobbler's awl beside them` |
| `G-07` | 墨水 | `a stoppered ink bottle beside a cut quill pen and a small horn inkwell` |
| `G-08` | 大麻纤维 | `a bundle of raw hemp stalks tied at the middle beside a coil of laid rope` |
| `G-09` | 蜡烛 | `three tallow candles of different lengths standing in a simple iron pricket holder` |
| `G-10` | 蜂蜜 | `a woven straw skep beside a dripping honeycomb section and a small sealed pot` |
| `G-11` | 煤 | `a heaped basket of rough coal lumps with a short shovel leaning against it` |
| `G-12` | 铁 | `a stack of rough iron blooms with a pair of blacksmith's tongs laid across them` |
| `G-13` | 木材 | `a stacked cord of split oak logs with a felling axe struck into the top one` |
| `G-14` | 奶酪 | `a whole round cheese with a wedge cut from it, resting on a slatted wooden drying board` |
| `G-15` | 白银 | `a small pile of hammered silver pennies beside a cast ingot with an assay mark` |
| `G-16` | 染料 | `three small open sacks of ground dyestuff, madder red, woad blue and weld yellow, with a stirring stick` |
| `G-17` | 纸 | `a stack of cut rag paper sheets weighted by a smooth stone, with one sheet curling at the corner` |
| `G-18` | 奴隶 | `a set of heavy iron shackles and a coil of rope on bare ground, grim and plain, no figures` |
| `G-19` | 陶器 | `three unglazed earthenware pots of different sizes nested together beside a potter's rib` |
| `G-20` | 陶土 | `a heaped mound of wet clay on a plank with a wire cutter and the mark of a thumb pressed into it` |
| `G-21` | 宝石 | `four cut and uncut gemstones on a folded cloth beside a pair of small brass tweezers` |
| `G-22` | 牛 | `a standing ox in profile with a yoke resting against its shoulder` |
| `G-23` | 白砂 | `a conical heap of pale sand on a coarse cloth with a wooden scoop pushed into it` |
| `G-24` | 葡萄酒 | `an oak wine barrel on its side with an iron-banded rim and a dark bunch of grapes on the vine leaf beside it` |
| `G-25` | 皮革 | `a rolled hide of tanned leather tied with cord beside a curved paring knife` |
| `G-26` | 锡 | `a stack of cast tin ingots with one stood on end to show its dull sheen` |
| `G-27` | 甘蔗 | `a bundle of cut sugarcane stalks tied at both ends beside a shallow boiling pan` |
| `G-28` | 大理石 | `two squared blocks of veined marble, one part dressed, with a mason's point chisel and mallet` |
| `G-29` | 毛皮 | `a rolled bundle of marten and fox pelts tied with cord, the tails hanging free` |
| `G-30` | 象 | `a working elephant in profile wearing a plain harness, standing calmly` |
| `G-31` | 猎物 | `a brace of hares and a plucked wildfowl hung from a stick with a hunting horn beside them` |
| `G-32` | 皂 | `four cut blocks of hard soap stacked in a pyramid beside a wooden mould` |
| `G-33` | 挽具 | `a coiled leather bridle, a curb bit and a horseshoe laid together` |
| `G-34` | 琥珀 | `a handful of rough amber pieces of different sizes on a dark cloth, one with an insect inside` |
| `G-35` | 工具 | `a hammer, a pair of pincers and a hand saw laid in a fan on a workbench` |
| `G-36` | 首饰 | `a chased silver brooch, a ring and a short strand of beads laid on a folded cloth` |
| `G-37` | 铜 | `a coil of drawn copper wire beside a beaten copper sheet with a hammered surface` |
| `G-38` | 羊 | `a standing sheep in heavy fleece in profile, with a pair of iron shears beside it` |

---

### 6.11 庄园彩绘 `B-`（2026-09-14 新增）

> **manor 信息卡顶部的建筑彩绘**（owner 2026-09-14）：点开一座 manor，左栏信息卡上方三分之一显示它的产业庄园画——和地图图例 `D-43`~`D-78` **一一对应**（十二种主业 × 小/中/大，同一 `key`，`assets/flux/estate_paint_art.csv`），但**风格与人物立绘一致**：§1.1 的 v2 彩铅 `STYLE_CORE.txt`（风格核本身就要求建筑与人物同样上色），画幅 `[C-ESTATE]`（5:4 横幅、边缘淡入奶油纸）。不去底、保留颜色，按用途装入 `assets/manors/paint/<key>.png`（信息卡画面约 216×190 设计像素 × 最大约 3 倍窗口缩放 → 720×576）。
>
> 主体沿用 `D-` 的内容（主宅 + 该产业的作业场），改成一幅上了色的乡间小景，允许几个劳作的小人物；不写"map symbol / flat side elevation"那类地图词。

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `B-01` | 庄园彩绘·粮田·小 | `a small grain holding: a thatched cottage beside one narrow strip field of ripening wheat, a wattle fence and a haystack, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-02` | 庄园彩绘·粮田·中 | `a grain manor: a stone farmhouse with a thatched barn, a windmill on a low mound, three strip fields of golden wheat in front, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-03` | 庄园彩绘·粮田·大 | `a great grain estate: a manor hall with a tithe barn, two windmills, a hamlet of thatched cottages, wide strip fields of golden wheat bounded by hedges, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-04` | 庄园彩绘·牧牛·小 | `a small cattle holding: a thatched cottage with a wattle-fenced paddock holding two brown cows, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-05` | 庄园彩绘·牧牛·中 | `a cattle manor: a stone farmhouse with a long byre, a fenced green pasture with a small herd of cattle and a wooden water trough, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-06` | 庄园彩绘·牧牛·大 | `a great cattle estate: a manor hall with two long byres, wide fenced green pastures with herds of cattle, a hamlet of cottages and a haystack yard, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-07` | 庄园彩绘·牧羊·小 | `a small sheep holding: a stone cottage with a dry-stone sheepfold holding a few white sheep on a grassy slope, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-08` | 庄园彩绘·牧羊·中 | `a sheep manor: a farmhouse with a shearing shed, a large stone-walled fold and a flock of sheep grazing on a low hillside, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-09` | 庄园彩绘·牧羊·大 | `a great sheep estate: a manor hall with a wool barn and shearing sheds, many stone-walled folds and flocks spread across rolling hills, a hamlet of cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-10` | 庄园彩绘·林场·小 | `a small timber holding: a woodcutter's cottage at the edge of an oak wood with a stack of cut logs and a few felled trunks, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-11` | 庄园彩绘·林场·中 | `a timber manor: a farmhouse with a saw-pit shed, stacks of seasoned timber and a coppice of broadleaf trees behind, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-12` | 庄园彩绘·林场·大 | `a great timber estate: a manor hall with long timber sheds and a saw-pit, great stacks of logs, carts of timber, a deep woodland behind and a hamlet of cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-13` | 庄园彩绘·蜂场·小 | `a small bee holding: a thatched cottage with three straw bee skeps on a wooden bench among wildflowers, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-14` | 庄园彩绘·蜂场·中 | `a honey manor: a farmhouse with a row of straw bee skeps under a lean-to and a small blossoming orchard, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-15` | 庄园彩绘·蜂场·大 | `a great honey estate: a manor hall with long benches of bee skeps under sheds, a large blossoming orchard and a hamlet of cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-16` | 庄园彩绘·葡萄园·小 | `a small wine holding: a stone cottage beside two rows of staked vines on a sunny slope, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-17` | 庄园彩绘·葡萄园·中 | `a wine manor: a stone farmhouse with a wine-press shed and oak barrels, terraces of staked vines climbing the slope, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-18` | 庄园彩绘·葡萄园·大 | `a great wine estate: a manor hall with a large press house and rows of oak barrels, wide terraced vineyards over the hills, a hamlet of cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-19` | 庄园彩绘·椰枣·小 | `a small date holding: a flat-roofed mud-brick cottage with three tall date palms in dry sandy country, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-20` | 庄园彩绘·椰枣·中 | `a date manor: a flat-roofed mud-brick house with a walled courtyard and a grove of date palms along an irrigation channel, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-21` | 庄园彩绘·椰枣·大 | `a great date estate: a large flat-roofed mud-brick house with towers, a wide grove of date palms along irrigation channels, a cluster of mud-brick cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-22` | 庄园彩绘·皮毛·小 | `a small trapping holding: a log cabin in a snowy clearing with a frame of stretched pelts drying beside it, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-23` | 庄园彩绘·皮毛·中 | `a fur manor: a timber lodge with drying frames of stretched pelts and a store hut, a dark conifer forest behind, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-24` | 庄园彩绘·皮毛·大 | `a great fur estate: a timber hall with long rows of drying frames of pelts, store houses and a cluster of log cabins before a conifer forest, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-25` | 庄园彩绘·渔业·小 | `a small fishing holding: a thatched cottage on the shore with one boat drawn up on the shingle and a net drying on a rack, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-26` | 庄园彩绘·渔业·中 | `a fishing manor: a stone house by a wooden jetty, three fishing boats drawn up, racks of drying nets and fish, the sea beyond, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-27` | 庄园彩绘·渔业·大 | `a great fishing estate: a manor house on the shore with a long stone quay, many fishing boats, smokehouses and drying racks, a row of fishermen's cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-28` | 庄园彩绘·盐田·小 | `a small salt holding: a cottage beside two rectangular salt pans of shallow shining water on a flat coast, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-29` | 庄园彩绘·盐田·中 | `a salt manor: a stone house with a salt store, a grid of rectangular salt pans, workers raking white heaps of salt, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-30` | 庄园彩绘·盐田·大 | `a great salt estate: a manor house with large salt stores, wide grids of rectangular salt pans, white heaps of salt and a row of workers' cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-31` | 庄园彩绘·采石·小 | `a small quarry holding: a cottage beside a small pale quarry face with a few cut stone blocks, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-32` | 庄园彩绘·采石·中 | `a stone manor: a stone house with a masons' shed, a quarry face with a wooden hoist and stacked cut blocks, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-33` | 庄园彩绘·采石·大 | `a great quarry estate: a manor house with masons' halls, a wide pale quarry face with hoists and wooden cranes, great stacks of cut blocks, a hamlet of cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-34` | 庄园彩绘·铁矿·小 | `a small mine holding: a cottage beside a timbered mine adit into a hillside with an ore cart, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-35` | 庄园彩绘·铁矿·中 | `an iron manor: a stone house with a bloomery furnace giving smoke, a timbered mine adit into the hill, ore carts and heaps of dark ore, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |
| `B-36` | 庄园彩绘·铁矿·大 | `a great iron estate: a manor house with several bloomery furnaces giving smoke, mine adits into the hill, ore carts on wooden rails, heaps of ore and a hamlet of cottages, shown as one painted scene of the whole holding in its own countryside, a few small figures at work` |

## 7. 战术地图元素 `W-`

> **风格设定**：这一层是「一个中世纪军事参谋在羊皮纸地图上画的作战标绘」。所以它比地图底层**更粗、更急、更手绘**——线条有起笔收笔的压力变化、有轻微抖动、颜色只用 oxblood（敌）/ verdigris（我）/ raw umber（中立）三色。
>
> **统一追加片段**（接在 `[S]` 之后、主体之前）：
> ```
> drawn hastily by hand directly onto a campaign map with a coloured pencil, visible
> pressure variation with heavier start and lighter release, slight tremor in the line,
> semi-transparent so the map beneath still reads,
> ```
> 全部使用 `[C-SYMBOL]` 收尾（透明背景、无场景、无透视）。
>
> **⚠️ 关于势力配色**：只生成 **umber 中性版本**，己方 verdigris / 敌方 oxblood 由代码染色。一个箭头生成三次三种颜色，是让风格飘掉的最快方式。

### 7.1 箭头类

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `W-01` | 进军箭头 | `a thick confident sweeping arrow curving from lower left to upper right, solid tapering shaft, a broad filled triangular head` |
| `W-02` | 快速突进 | `a long narrow arrow with a sharply raked barbed head and three short speed strokes trailing behind the tail, drawn fast and lightly` |
| `W-03` | 迂回包抄 | `a wide crescent arrow sweeping outward and then hooking sharply back inward, the head turning almost 180 degrees to point back at the origin side` |
| `W-04` | 钳形攻势 | `a matched pair of mirrored curving arrows converging from opposite sides toward a single point between them, heads nearly touching` |
| `W-05` | 佯攻 | `a dashed hollow arrow, the shaft made of short broken segments and the head drawn as an unfilled outline only, deliberately tentative` |
| `W-06` | 撤退 | `an arrow with a straight shaft and an open V-shaped head, drawn in thin uncertain line with the tail fading out into nothing` |
| `W-07` | 溃退 | `a ragged arrow breaking apart along its length into scattered disconnected strokes, the head fragmented, chaotic and falling apart` |
| `W-08` | 补给线 | `a long thin arrow whose shaft is a chain of small evenly spaced circles connected by a hairline, with a tiny open head` |
| `W-09` | 海军航线 | `a smoothly undulating arrow following a shallow S-curve, the shaft drawn as a double hairline with the space between left open, a slender swallowtail head` |
| `W-10` | 增援 | `a short straight arrow with a doubled chevron head and two parallel bars crossing the shaft near the tail` |

### 7.2 战线与区域

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `W-11` | 战线 | `a long irregular hand-drawn frontier line with a row of short perpendicular ticks along one side, like a military front marked on a staff map` |
| `W-12` | 推进的战线 | `a bulging frontier line pushed forward into a salient, with short forward-pointing ticks along the convex side and hatching filling the gained ground` |
| `W-13` | 控制区填充 | `an irregular closed region filled with sparse loose diagonal hatching, the boundary a wavering hand-drawn line, the hatching thinning out toward the edges` |
| `W-14` | 争夺区 | `an irregular region filled with two sets of hatching crossing at right angles from opposite directions, creating a dense contested lattice` |
| `W-15` | 包围圈 | `a closed irregular ring of short inward-pointing arrow strokes surrounding an empty centre, tightening and overlapping at the top` |
| `W-16` | 封锁线 | `a straight double line with a row of small solid squares strung along it at even intervals, drawn firmly` |
| `W-17` | 设防阵地 | `a line of small repeated bastion shapes, alternating triangular points and short crenellations, forming a defensive earthwork symbol` |
| `W-18` | 行军路线 | `a long meandering dotted route line following terrain, with small tick marks at intervals and a tiny open circle at each end` |

### 7.3 单位棋子

> **画幅调整**：单位棋子用 `[C-ICON]` 而非 `[C-SYMBOL]`（它们是有体积的小物件，不是平面符号）。
>
> **统一追加**：`rendered as a small carved and painted wooden campaign-table gaming piece standing upright on a round base, seen at a low three-quarter angle`

| ID | 单位 | Prompt 主体 |
|---|---|---|
| `W-19` | 重骑兵 | `a mounted knight in mail with a couched lance and a kite shield, the horse in caparison at a walk` |
| `W-20` | 轻骑兵 | `a light horseman without armour holding a javelin, the horse lean and unbarded, alert posture` |
| `W-21` | 重步兵 | `a foot soldier in mail hauberk and kettle hat with a large shield and a spear held upright` |
| `W-22` | 长枪方阵 | `three foot soldiers packed shoulder to shoulder behind a hedge of long pikes angled forward at the same rake` |
| `W-23` | 长弓手 | `an unarmoured archer standing with a tall unstrung warbow grounded beside him and a quiver at the hip` |
| `W-24` | 弩手与大盾 | `a crossbowman standing behind a tall rectangular pavise shield propped on the ground, crossbow held across the body` |
| `W-25` | 攻城器 | `a small trebuchet with its counterweight raised and its throwing arm cocked, on a timber frame` |
| `W-26` | 辎重队 | `a two-wheeled ox cart piled with barrels and sacks under a lashed cover, one ox in the traces` |
| `W-27` | 战船 | `a single-masted clinker-built cog with a furled square sail, fore and after castles and a steering oar` |
| `W-28` | 征召民兵 | `two poorly equipped peasant levies with a spear and a bill hook, no armour, one wearing only a padded jack, ragged and uneven` |

### 7.4 事件与状态标记

| ID | 对象 | Prompt 主体 |
|---|---|---|
| `W-29` | 会战地点 | `two short crossed swords drawn boldly with a small burst of radiating strokes behind them` |
| `W-30` | 围城 | `a small crenellated tower outline encircled by a ring of short inward strokes, with one wall segment drawn broken` |
| `W-31` | 扎营 | `a simple conical campaign tent with a guy rope and a pennon on its peak, and a small ring of stones with three smoke strokes beside it` |
| `W-32` | 集结点 | `a plain vertical staff with a small triangular pennon, its base marked by a ring of short converging strokes` |
| `W-33` | 伏击 | `a hooked barbed shape half-concealed behind three short screening strokes, drawn faintly as if partly erased, ambiguous` |
| `W-34` | 战略目标 | `a hand-drawn ring with a small solid dot at its centre and four short radiating ticks at the cardinal points` |
| `W-35` | 要害隘口 | `two short opposed bracket strokes with a narrow gap between them and a small X marked in the gap` |
| `W-36` | 减员 | `a small cluster of three short crossed strokes forming rough X marks of decreasing size, scattered irregularly` |
| `W-37` | 胜利 | `a laurel sprig curving upward with a small pennon flying from its tip, drawn in a single confident stroke` |
| `W-38` | 败北 | `a broken staff snapped at the middle with a torn pennon hanging limp from the upper fragment` |

---

## 8. 事件插图 `V-`

> **用途**：事件弹窗配图，横构图 3:2，建议 1536×1024。
>
> **⚠️ 生产方法（不要跳）**：事件插图是多人物、有构图、有透视的场景，**纯 prompt 出图的失败率极高**（人物粘连、手脚错乱、建筑透视崩）。正确流程：
> 1. Blender 里用最粗糙的胶囊体人偶摆位，5 分钟定构图和机位
> 2. 导出 depth + openpose
> 3. ControlNet 双条件约束 + style LoRA 生成
> 4. 局部重绘修脸和手，通常要 20–40 次
>
> 所有 prompt 前接 `[S]`、后接 `[C-SCENE]`。**画面中绝对不能出现文字**（负面词里已含 `printed typography, lettering`，但事件图里旗帜、书页、招牌容易诱发文字，生成后要专门检查）。

### 8.1 阴谋与暗杀

#### `V-01` 暗杀 · Assassination
```
[S] a night interior of a stone bedchamber lit only by one guttering candle, a hooded
figure standing over a canopied bed with a narrow dagger already descending, the sleeping
victim's hand flung out across the coverlet, a heavy tapestry still swinging where the
killer entered, deep raw umber shadows swallowing three quarters of the frame, a single
warm ochre pool of light on the bed, extreme tonal contrast, tension held in the moment
before contact [C-SCENE]
```

#### `V-02` 密谋 · The Conspiracy
```
[S] five cloaked figures leaning inward around a small table in a low vaulted undercroft,
a single candle at the centre uplighting their faces from below so the eye sockets fall
into shadow, one hand pointing at a folded document on the table, another hand gripping a
wrist to silence someone, one figure half turned watching the door, hunched conspiratorial
body language, cold slate shadows against the one warm light source [C-SCENE]
```

#### `V-03` 下毒 · The Poisoned Cup
```
[S] a crowded feast hall seen past a foreground shoulder, in the mid ground a servant's
hand tipping a tiny phial over a silver goblet on a tray, everyone else in the hall
laughing and turned away, the poisoner's face utterly calm and looking straight ahead,
warm ochre torchlight throughout, the single act of poisoning rendered slightly sharper
and more contrasted than everything around it [C-SCENE]
```

#### `V-04` 背叛败露 · The Betrayal Revealed
```
[S] a great hall interior, a lord standing frozen at the centre holding an intercepted
letter with a broken seal, his face going white, a ring of courtiers drawn back from him
leaving a circle of empty floor, two guards already stepping in from the edges of the
frame, everyone's eyes on the man, cold grey daylight from high windows, the composition
isolating him in the middle of a widening gap [C-SCENE]
```

#### `V-05` 囚禁 · Imprisonment
```
[S] a cramped circular tower cell, a single high barred window casting one hard shaft of
pale slate light onto a straw covered floor, a gaunt prisoner sitting against the curved
wall with wrists chained and knees drawn up, head tilted back against the stone, a
untouched wooden bowl beside him, the rest of the cell in deep umber gloom, silence and
stillness [C-SCENE]
```

#### `V-06` 私通败露 · The Discovered Affair
```
[S] a bedchamber door flung open, the figure in the doorway silhouetted black against
bright corridor light, inside two figures caught turning toward the door in disarray, one
half risen from the bed clutching a robe, faces stricken, an overturned stool, strong
backlight from the door and dim warm interior light, the composition split hard between
the lit doorway and the dark room [C-SCENE]
```

### 8.2 战争

#### `V-07` 会战 · The Pitched Battle
```
[S] a mass medieval battle at the moment of collision seen from a slight elevation, two
armies interpenetrating in a churning line across the middle third of the frame, a hedge
of levelled spears, banners tilting, a fallen horse, dust and smoke rising to flatten the
background into pale grey, individual figures readable only in the foreground and
dissolving into massed hatching further back, chaotic but with a clear left-right
compositional axis [C-SCENE]
```

#### `V-08` 部队列阵 · The Army Arrayed
```
[S] a medieval army drawn up in formation before battle seen from the flank, three
distinct blocks in depth, a solid front rank of shields, a bristling forest of upright
spears above them, mounted knights massed on the wing, banners hanging still in the
windless air, a mounted commander in the foreground with his back to the viewer looking
down the line, early morning mist in the low ground, absolute order and stillness
[C-SCENE]
```

#### `V-09` 进军 · The March
```
[S] a long medieval column on the move receding into distance along a rutted track, foot
soldiers with spears sloped over shoulders in loose ranks, baggage carts and pack mules,
a mounted vanguard cresting a low rise, the column narrowing to a thin line at the horizon,
churned mud, grey overcast light, a strong diagonal recession from lower left to upper
right, weariness in every posture [C-SCENE]
```

#### `V-10` 骑兵冲锋 · The Cavalry Charge
```
[S] a wedge of armoured knights at full gallop coming almost directly at the viewer,
lances couched and levelled, horses at full stretch with clods flying, caparisons
streaming, the front rank in sharp detail and the ranks behind dissolving into speed
strokes and dust, low camera angle from just above ground level, tremendous forward
momentum, the frame filled with converging diagonals [C-SCENE]
```

#### `V-11` 攻城 · The Assault
```
[S] a medieval castle wall under escalade assault, three siege ladders against the
crenellations crowded with climbing men-at-arms, a defender toppling backward off the
parapet, stones and burning bundles falling, a siege tower being pushed into position at
the left, arrows in flight rendered as fine hard strokes, smoke rolling across the wall
top, seen from an angle low and outside the wall so the wall looms [C-SCENE]
```

#### `V-12` 围城营地 · The Siege Camp
```
[S] a besieging army encamped before a distant walled town at dusk, ordered rows of
conical tents with cooking fires and smoke columns, a trebuchet standing silhouetted, men
sitting idle around fires, a supply cart arriving, the town wall a thin grey line on the
horizon, long low shadows, a mood of patient grinding boredom rather than action [C-SCENE]
```

#### `V-13` 城破 · The Sack
```
[S] a medieval town street after the walls have fallen, buildings burning in the mid
ground throwing hard orange light, figures fleeing across the foreground, soldiers
carrying off bundles, a broken door hanging from one hinge, smoke blotting out the upper
third of the frame, the light source low and violent, deep oxblood and umber palette,
composed so the viewer's eye is led down the street into the fire [C-SCENE]
```

#### `V-14` 敌军进犯 · The Enemy Approaches
```
[S] a view from atop a castle wall looking out over the countryside, two watchmen in the
foreground seen from behind gripping the parapet, one pointing, and on the far horizon a
long dark line of an approaching army with a haze of dust above it and a scatter of
banners, burning farmsteads sending up thin smoke columns closer in, cold grey blue light,
the threat kept small and distant to make it worse [C-SCENE]
```

#### `V-15` 海战 · The Sea Battle
```
[S] two medieval cogs grappled together in a heavy grey sea, boarding planks thrown
across, men fighting hand to hand along the gunwales and in the fore castles, an archer
in the fighting top, a broken mast, spray and slate blue water crowding the lower frame,
overcast sky, the two hulls forming a strong X composition [C-SCENE]
```

#### `V-16` 劫掠 · The Raid
```
[S] mounted raiders sweeping through an undefended village, a thatched roof already
alight, livestock being driven off, a rider leaning from the saddle with a torch, peasants
scattering toward the treeline in the foreground, everything in motion and nothing
resisting, harsh diagonal composition, warm fire light against a cold dawn sky [C-SCENE]
```

#### `V-17` 决斗 · The Judicial Duel
```
[S] two armoured men fighting on foot inside a roped and staked lists, one driven to one
knee with his shield split, the other bringing an axe down, a marshal with a raised staff
at the edge ready to stop it, a tight ring of silent spectators pressed against the ropes
all around, flat overcast light, the two fighters isolated in an empty trampled circle of
earth [C-SCENE]
```

#### `V-18` 比武大会 · The Tournament
```
[S] a medieval tournament, two knights meeting at the tilt barrier with lances shattering
into flying splinters, horses at full stride, a crowded gallery of nobles under striped
awnings on one side and standing commons on the other, banners and caparisons in muted
heraldic colours, dust kicked up along the barrier, bright but overcast day, festive
energy [C-SCENE]
```

### 8.3 统治与内政

#### `V-19` 收税 · The Tax Collection
```
[S] a village green with a tax official seated behind a trestle table under a bare tree,
a wax tablet and a tally stick before him, a queue of peasants waiting with sacks and
coins, one man at the table turning out an empty purse with both hands while the official
looks away unmoved, two armed serjeants standing behind the table with hands on their
belts, flat grey daylight, quiet humiliation rather than violence [C-SCENE]
```

#### `V-20` 百姓暴动 · The Peasant Revolt
```
[S] a mob of peasants surging up a village street armed with billhooks, threshing flails,
scythe blades lashed to poles and one stolen sword, faces contorted with shouting, a
rough banner of a plain cloth on a pole, a manor gate ahead of them already smoking, the
crowd rendered as a dense mass of raised implements against a pale sky, strong upward
diagonal, ugly and unstoppable [C-SCENE]
```

#### `V-21` 游行示威 · The Procession of Grievance
```
[S] a long orderly crowd of townspeople moving through a market square, not violent but
grimly determined, walking in a mass with linked arms at the front rank, guild banners of
plain cloth held up, women and children among them, a line of nervous serjeants with
spears held horizontally holding a line across the square ahead, the two groups not yet
touching, flat grey light, the tension entirely in the gap between them [C-SCENE]
```

#### `V-22` 加冕 · The Coronation
```
[S] a cathedral interior interior at the moment of crowning, a kneeling figure at the
centre with a bishop lowering a crown onto the head with both hands, ranks of clergy and
nobles receding into the aisles, tall candles, censer smoke catching a shaft of coloured
light from a high window, deep architectural perspective converging on the crown, solemn
and vertical [C-SCENE]
```

#### `V-23` 封臣宣誓 · The Oath of Fealty
```
[S] a great hall interior, a kneeling vassal with both hands placed together between the
seated lord's two hands in the gesture of immixtio manuum, their eyes locked on each
other, a ring of witnesses standing back at a respectful distance, a clerk recording at a
side table, cool light from high windows falling on the joined hands at the exact centre
of the frame [C-SCENE]
```

#### `V-24` 贵族会议 · The Council
```
[S] a council chamber with eight nobles and clerics seated around a long table, one
standing and leaning forward with both fists on the table arguing, two others turned
toward each other in private conference, one sitting back with arms folded and eyes
closed, a map and rolls spread across the table, cold north light from a tall window,
every figure with a distinct posture and allegiance readable from body language [C-SCENE]
```

#### `V-25` 审判 · The Trial
```
[S] a hall of justice, a lord seated elevated on a dais under a canopy, a bound accused
standing below flanked by two serjeants, a clerk reading from a roll, a small crowd of
onlookers packed at the back, the composition strongly vertical with the judge high and
the accused low, hard light from one side, the accused rendered slightly smaller in scale
than the perspective strictly warrants [C-SCENE]
```

#### `V-26` 处决 · The Execution
```
[S] a public execution in a town square at dawn, a low timber scaffold with a block, a
kneeling condemned figure and an executioner with a raised axe, a priest holding a cross
at the edge of the platform, a dense silent crowd filling the square below with a few
faces turned away, thin cold light, the crowd rendered as massed grey hatching and the
scaffold left as the only clearly lit element [C-SCENE]
```

#### `V-27` 出使谈判 · The Embassy
```
[S] a formal reception, an envoy in travelling dress standing and presenting a sealed
document held out on both palms, a seated ruler receiving it with visible reluctance,
their respective retinues arranged in two opposing blocks behind them with a clear empty
aisle between, mirrored composition, cool even light, mutual distrust legible in every
face [C-SCENE]
```

#### `V-28` 签订和约 · The Treaty
```
[S] two parties at a long table in a tent, each principal setting a seal matrix into
warm wax on a document, clerks steadying the parchment, the retinues standing behind in
two blocks, one man on each side watching the other's hands rather than the document,
warm filtered light through canvas, an outwardly ceremonial and inwardly cold mood
[C-SCENE]
```

### 8.4 灾变与社会

#### `V-29` 瘟疫 · The Pestilence
```
[S] a narrow town street during plague, a cart of shrouded bodies being pulled away, a
door marked with a rough cross, a hooded figure with a cloth over the face carrying a
censer, one collapsed figure against a wall, shuttered windows all along the street, a
dog the only thing moving freely, drained desaturated palette leaning grey green, empty
and silent [C-SCENE]
```

#### `V-30` 饥荒 · The Famine
```
[S] a bare winter field with a failed crop, a gaunt family standing in the furrows, a
mother holding a listless child, a father staring at the empty ground with a spade hanging
from one hand, a bare tree with the bark stripped off at head height, crows on the branches,
low flat grey light, the horizon high in the frame pressing down on the figures [C-SCENE]
```

#### `V-31` 丰收 · The Harvest
```
[S] a harvest field in full late summer, reapers moving through standing wheat with
sickles, women binding sheaves behind them, stooks already standing in rows, a cart being
loaded, a jug being passed, children gleaning, warm golden ochre throughout with deep
umber shadows, a low sun raking across from the left, the one genuinely warm and generous
composition in the set [C-SCENE]
```

#### `V-32` 朝圣 · The Pilgrimage
```
[S] a line of pilgrims on a road with staffs and scrips, a scallop badge on one hat,
several barefoot, one being helped along, cresting a rise from which a distant cathedral
is visible small on the horizon, dust on everything, long shadows of late afternoon, the
road forming a strong receding diagonal toward the far spire [C-SCENE]
```

#### `V-33` 火灾 · The Great Fire
```
[S] a medieval town quarter burning at night, a bucket chain of townspeople running from
a well toward the flames, a timber-framed house collapsing inward with sparks fountaining
up, silhouetted figures against the fire, the upper half of the frame filled with rolling
smoke lit orange from beneath, the foreground figures in near silhouette, violent light
[C-SCENE]
```

#### `V-34` 天象异兆 · The Omen
```
[S] a night sky over a sleeping medieval town with a great comet hanging above it, its
tail drawn as long fine converging pencil strokes, townspeople in the street below in
nightclothes staring upward, one kneeling, one pointing, one covering a child's eyes, the
town rendered dark and small at the bottom fifth of the frame and the sky given everything
above, cold slate blue with the comet in pale ochre [C-SCENE]
```

---

## 9. UI 框架件 `U-`

> **风格核**：`STYLE_CORE_ui_vellum.txt` + `NEGATIVE_ui_vellum.txt`（附录 A / B 第三段），不是 §1.1 的 v2。2026-09-12 出过一批样张，两个现成风格核都不成立：v2 明确要求"干净纸底、不做旧"，和条目里的 `aged vellum` 直接打架；v1 做旧核把物件和底色染成同一个色调，没有剪影可抠，做不成 9-slice。
>
> **画幅**：方件用 `[C-UIPIECE]`，长条件（`U-03`/`U-08`/`U-13`/`U-17`）跑的时候加 `--canvas C-UIWIDE`。两者都把物件**铺满画框**——`[C-ICON]` 的"generous margin"会让按钮和分隔线这种小物件缩成画框中央的一个小点（同一批样张里 `U-04`、`U-08` 就是这么废的），也都把底色定成**中性灰**，而不是纸色：UI 件本身就是一张纸，底色再是纸色就抠不出来了（`D-` 那条白底转 alpha 的路子在这里不成立，要走 BiRefNet）。
>
> **切图要求**：所有面板、按钮、边框都必须做成 **9-slice（九宫格）** 可拉伸资源。所以条目里**不能出现** `irregular hand-cut edges` / `deckled edge` / `hand-drawn edge` 这类词——手工毛边和九宫格拉伸是互斥的：四个角必须能互换，中间必须能无痕重复。风格核里已经写死了 `straight true edges` 和 `exactly repeating spacing`。
>
> **`U-19` 的中间要画满、不要留黑**（2026-09-12）：上一版画框走的是「黑心 + `tools/key_frame_interior.py` 抠成透明」，为的是透出背后的地图底。羊皮纸主题下不需要了——中间就是一张米色羊皮，标题和按钮直接压在上面，抠图那一步整个省掉。
>
> **这一章有一半不该出图**（2026-09-12 结论）：`U-08` 分隔线、`U-10`/`U-11` 圆头像框、`U-13` 进度槽、`U-14` 滚动条、`U-18` 纹章盾全是几何形，代码画又准又能随时改色、随分辨率清晰，位图反而更死——`scripts/ui/heraldic_shield.gd` 已经是这么做的。下表里这些条目标了 **代码绘制**，保留只是为了留个设计描述，不要拿去跑批。真正值得出图的是有材质和手工感的那几件：`U-01`、`U-03`、`U-12`、`U-17`。
>
> **这一章分三类跑**（2026-09-12 逐条试出来的）：
>
> | 类 | 条目 | 怎么跑 |
> |---|---|---|
> | 可拉伸的羊皮纸部件 · 方 | `U-01` `U-02` `U-12` | `--style-file STYLE_CORE_ui_vellum.txt`（画幅取默认的 `[C-UIPIECE]`）|
> | 可拉伸的羊皮纸部件 · 长条 | `U-03` `U-04` `U-07` | 同上，加 `--canvas C-UIWIDE` |
> | 独立物件（不拉伸） | `U-09` 角饰、`U-15` 提示纸条、`U-16` 蜡封、`U-17` 缎带 | **默认 v2 核**，`--canvas C-ICON`（`U-15`/`U-17` 用 `C-UIWIDE`）|
> | 满屏画框 | `U-19` 主菜单画框 | **默认 v2 核**，`--canvas C-FRAME`，出完过 `post.py --tone` |
> | 代码绘制 | `U-05` `U-06` `U-08` `U-10` `U-11` `U-13` `U-14` `U-18` | 不出图 |

> **按钮三态只出一张**（2026-09-12）：`U-05` 按下态和 `U-06` 禁用态**不要生成**。条目文本写的是"同一个按钮，倒过来打光/褪色"，klein 4B 读不出这种差分——三张跑出来肉眼无法区分。按下=`U-04` 压暗加一两像素偏移，禁用=去饱和降透明度，在 Godot 里是 `StyleBoxTexture` 的 `modulate_color`，两行的事，而且永远和常态对得上。条目保留作设计描述。

> **方长之分不是美观问题**：`[C-UIPIECE]` 会把物件铺满整个方画框，按钮和标签页跑成方的就没有"边"可以打斜面了——`U-04` 用方画幅出来是一整块平板，改成 `[C-UIWIDE]` 才有上下两道斜面带。`U-09` 角饰同理：它是一个小母题，铺满画框只会变成"一张带角饰的面板"，得当独立物件跑。
>
> 第二类是硬碰出来的结论，不是口味问题：UI 风格核里的 `manuscript furniture`、`the centre of any panel left plain`、`every run that will be stretched` 这些词专门为九宫格服务，套到不拉伸的物件上会把它们拉平——`U-16` 被画成了一张证书面板，`U-17` 的燕尾缺口连换四个 seed 都被压成方盒子。换回 v2 核，同样的 seed 一次就对。

| ID | 对象 | Prompt 主体（前接 `[S]`，后接 `[C-UIPIECE]`） |
|---|---|---|
| `U-01` | 主面板 | `a rectangular panel of pale vellum with straight true edges, a fine double-ruled umber border inset evenly from the edge, small matching foliate ornaments at the four corners only, the entire centre left as plain empty vellum` |
| `U-02` | 次级面板 | `a smaller plain vellum panel with a single thin ruled border set evenly inside a straight clean edge, no ornament at all, the centre completely empty` |
| `U-03` | 卷轴条 | `a horizontal strip of vellum with both ends rolled into tight scrolls around thin turned wooden rods, the long flat centre span left blank and perfectly even in height` |
| `U-04` | 按钮 · 常态 | `a rectangular tab of stiff vellum with a fine ruled edge and a raised bevel indicated by even shading along the top and left, straight edges, centre plain` |
| `U-05` | 按钮 · 按下 | `the same rectangular vellum tab pressed inward, the bevel shading inverted to the bottom and right, slightly darker overall, straight edges, centre plain` |
| `U-06` | 按钮 · 禁用 | `the same rectangular vellum tab in flat pale grey umber with no bevel shading and a faded edge, straight edges, centre plain` |
| `U-07` | 标签页 | `a vellum index tab with straight sides, a squared outer edge, a fine ruled outline and a small leather lacing hole at one side, blank face` |
| `U-08` | 分隔线 · **代码绘制** | `a slender horizontal rule consisting of a fine umber line with a small centred diamond lozenge and two tiny opposing leaf forms, symmetrical` |
| `U-09` | 角饰 | `a single foliate corner ornament of curling acanthus in raw umber with one verdigris accent leaf, drawn for the top-left corner, its two straight outer edges meeting at a true right angle` |
| `U-10` | 头像框 · 平民 · **代码绘制** | `a plain circular frame of a single thin umber ruled line, the interior empty` |
| `U-11` | 头像框 · 贵族 · **代码绘制** | `a circular frame of a double ruled line with a narrow band of evenly repeating foliate scroll between the rules and four small bosses at the cardinal points, interior empty` |
| `U-12` | 头像框 · 王室 | `an ornate circular frame drawn as flat inked vellum ornament, a double rule enclosing a dense band of evenly repeating interlaced foliage, four small jewelled bosses and a small open crown cresting the top, interior empty` |
| `U-13` | 进度条 · **代码绘制** | `a long narrow horizontal trough drawn as a double ruled channel with evenly spaced tick divisions along its length, the interior left entirely empty` |
| `U-14` | 滚动条 · **代码绘制** | `a slender vertical channel with a small oval sliding thumb rendered as a polished bone bead, drawn simply` |
| `U-15` | 提示气泡 | `a small vellum slip with one softly torn edge and a slight curl at one corner, the face completely blank` |
| `U-16` | 蜡封印章 | `a round blob of deep oxblood sealing wax with irregular squeezed edges and a pressed intaglio device of a blank shield` |
| `U-17` | 缎带标题条 | `a horizontal banderole ribbon of vellum, each end folded sharply back on itself and cut into a deep V-notched swallowtail point, the broad flat centre band between the folds left completely blank and even in height` |
| `U-19` | 主菜单画框 | `a deliberately asymmetric illuminated border. A handsome middle-aged crowned king occupies the BOTTOM LEFT corner alone — a strong-jawed man of about forty-five, short dark hair greying at the temples under a gold circlet, a close-trimmed beard, seated and turned three-quarters, his head tilted up and back so that he looks UP the diagonal, one small carved chess piece held between finger and thumb at chin height, brow drawn, deep in thought — his head reaching no higher than the middle of the frame. A much older grey-bearded lord occupies the TOP RIGHT corner alone, seated high with his chin resting on his hand, his head close to the top edge, looking back down at the younger man. There is no table, no board, no chessboard anywhere in the frame — only the two men, the single piece in the king's hand, and the ornament. The top left corner and the bottom right corner hold nothing but vine scrollwork and a heraldic lion. A small open crown at the top centre` | 主菜单画框 | `a deliberately asymmetric illuminated border. A young clean-shaven crowned lord occupies the BOTTOM LEFT corner alone, seated low and leaning forward on one elbow, his head reaching no higher than the middle of the frame. A much older grey-bearded lord occupies the TOP RIGHT corner alone, seated high with his chin resting on his hand, his head close to the top edge. The two look steadily at each other along the diagonal across the empty middle, two players caught between moves. There is no table, no board, no chessboard and no game pieces of any kind anywhere in the frame — only the two men and the ornament. The top left corner and the bottom right corner hold nothing but vine scrollwork and a heraldic lion. A small open crown at the top centre` | 主菜单画框 | `a deliberately asymmetric illuminated border. A young clean-shaven crowned lord occupies the BOTTOM LEFT corner alone, seated low over a chessboard on the table in front of him, his head reaching no higher than the middle of the frame. A much older grey-bearded lord occupies the TOP RIGHT corner alone, seated high with his own carved pieces before him, his head close to the top edge. The two look at each other along the diagonal across the empty middle. The top left corner and the bottom right corner hold nothing but vine scrollwork, a heraldic lion and a few scattered carved chess pieces. A small open crown at the top centre` | 主菜单画框 | `a young crowned lord seated in the LOWER LEFT corner and a much older bearded lord seated in the UPPER RIGHT corner, the two of them playing one long game of chess against each other diagonally across the empty middle of the frame, each leaning over the chessboard on the small table before him and looking toward the other, the young one clean-shaven in a bright mantle and the old one grey-bearded and heavy-browed, both worked into the border ornament rather than staged as a scene, the rails between them filled with running vine scrollwork, a heraldic lion in the upper left corner and another in the lower right, a small open crown at the top centre` | 主菜单画框 | `two seated medieval lords facing one another across one single chessboard standing in the middle of the bottom rail, one lord to the left of that board and one to its right and no other board anywhere, both drawn small and absorbed into the border ornament rather than staged as a scene, the side rails filled with running vine scrollwork, a heraldic lion at each of the two top corners, a small open crown at the top centre` |
| `U-18` | 空白纹章盾 · **代码绘制** | `an empty heraldic shield of classic heater shape with a fine umber outline and a very subtle interior shading suggesting slight convexity, the field left entirely blank for programmatic colouring` |

---

## 10. 生产流程与质检

### 10.1 三阶段流程

```
阶段一 · 风格锁定（1–2 周，最关键）
  只用 [S]，不训任何模型
  跑 C-01~C-05、V-07、V-19、M-03、I-04、T-01、W-01
  → 这 10 张覆盖了全部资源类型。看它们能不能像一套东西。
  → 不满意就改 [S] 重跑。改到满意为止。这一步做不好，后面全部返工。

阶段二 · 训练风格锚（3–5 天）
  从阶段一挑 30–40 张最好的 → 训 style LoRA
  验证：用 LoRA 重跑阶段一那 10 张，看一致性有没有提升

阶段三 · 量产（按资源类型并行）
  人物线：角色 LoRA → 立绘 → 表情差分 → 姿态差分
  地图线：GIS 数据 → QGIS 素图 → ControlNet + LoRA → 瓦片
  图标线：批量生成 → 去背 → 三档尺寸 → 染色测试
  事件线：Blender 摆位 → ControlNet → 局部重绘（最慢，最先开工）
```

### 10.2 Style LoRA 训练配方

| 项 | 建议 |
|---|---|
| 底模 | Flux.1 dev（彩铅质感表现最好）；备选 Qwen-Image |
| 训练集 | 30–40 张，**必须覆盖所有资源类型**（人物 15 / 场景 8 / 地图 5 / 图标 7），否则地图和图标会被人物风格带偏 |
| 分辨率 | 统一 1024×1024（长图先裁成方图） |
| 触发词 | 起一个不会撞词的，如 `mdvlcp` |
| 打标 | 只标**内容**，不标风格。风格描述全部剔除——那是要让模型学进权重里的东西 |
| 学习率 / step | 常规风格 LoRA 设置即可，宁可欠拟合。过拟合的表现是所有图开始长得像训练集里的某一张 |
| 平台 | Scenario Pro（$45/月，省事）或本地 ComfyUI + ai-toolkit |

### 10.3 角色 LoRA（只给主要角色做）

1. 用 style LoRA 跑 `C-xx` 的 prompt 30–50 次
2. 人工挑出 **20–25 张五官最一致**的（这一步只能人工，别偷懒）
3. 用这批训 character LoRA
4. 生成时 **style LoRA + character LoRA 双挂**，character 权重 0.7–0.9

### 10.4 工作量估算

| 类别 | 资源数 | 含变体后图数 | 主要瓶颈 |
|---|---|---|---|
| 人物立绘 | 55 | ~470 | 角色 LoRA 训练与筛图 |
| 地图底图 | 14 | 6 zoom × N 区域 | GIS 数据准备 |
| 地形贴图 | 20 | ~100（每种 5 变体） | 无缝平铺验证 |
| 地图图标 | 42 | 126（三档尺寸） | 去背质量、小尺寸可读性 |
| 战术元素 | 38 | 38（染色由代码做） | 透明背景干净度 |
| 事件插图 | 34 | 34 | **局部重绘，每张 20–40 次迭代** |
| UI 件 | 18 | ~40（含状态） | 9-slice 切图 |

**事件插图是整个项目的关键路径**，虽然只有 34 张，但单张耗时是立绘的 5–10 倍。**建议最先开工。**

### 10.5 风格一致性 checklist（每批图过一遍）

- [ ] `[S]` 是否逐字来自 `STYLE_CORE.txt`，没有任何人手改过
- [ ] 纸底色是否统一为 Cream Laid `#EDE3CE`（把整批图并排铺开看，色温飘的一眼可见）。**2026-09-12 起这条有自动化**：`post.py --tone` 量出源图的纸底、算逐通道增益、白平衡到 `#EDE3CE`。不同风格核之间飘得很厉害——§9 的 UI 部件量到 `#DEC5A3`，同一章的独立物件量到 `#FBF7E7`，亮度差 48 级、暖度（R−B）差三倍，肉眼在单张上看不出来，并排就炸。
- [ ] 是否出现了 1.4 调色板之外的主色相
- [ ] 铅笔颗粒感是否还在（放大器最容易把它抹平）
- [ ] 线条是否仍无墨线轮廓（负面词失效时 AI 会偷偷加黑边）
- [ ] 光照方向是否一致（本项目统一：**柔和阴天顶光偏左**）
- [ ] 把新一批图和阶段一的 10 张基准图并排——像不像一套

### 10.6 历史考据 checklist

- [ ] **年代**：全部资源统一在 1050–1350。**最常见的翻车是全身板甲**（15 世纪才成熟），负面词已含 `plate armour before 1400`，但仍要逐张看
- [ ] **服饰**：13 世纪前女性已婚必戴头巾（wimple/veil）；纽扣在 13 世纪中后期才普及；紧身 cotehardie 属 14 世纪
- [ ] **武备**：链甲为主；大剑十字护手形制；**绝不能出现角盔**（纯属 19 世纪虚构）
- [ ] **建筑**：罗马式圆拱 vs 哥特式尖拱不要混在同一座建筑上；飞扶壁属 12 世纪末以后
- [ ] **作物与物产**：**没有**辣椒、玉米、番茄、土豆、烟草、向日葵（全是 1492 后的美洲作物）
- [ ] **器物**：机械钟 14 世纪才出现；眼镜 13 世纪末才有且极罕见；纸张在西欧要到 13 世纪后期
- [ ] **文字**：AI 生成的任何文字都是乱码。旗帜、书页、招牌、地图标注上的字**全部手动重画或用矢量文字层叠加**
- [ ] **族群刻画**：异邦角色（`C-51`~`C-55`）一律按有尊严的专业人士刻画，避免刻板化脸谱

### 10.7 技术规格（2026-09-11 按游戏实际改写）

游戏的设计视口是 **640×360**，窗口 1280×720（2×，`canvas_items` 拉伸），像素字体、nearest 过滤。所有资源都按「Flux 原生 1024 级生成 → 去底 → 缩到游戏尺寸」走，缩放和去底由 `assets/flux/post.py` 做，不手工。数字是**交付给引擎的尺寸**，不是生成尺寸。

| 资源类型 | 生成 | 交付 | 格式 | 备注 |
|---|---|---|---|---|
| 对话头像 `[C-BUST]` | 1024×1024 | **96×96** | PNG 带 alpha | 头像格 48 设计像素，2× 即 96；`post.py --tier chip` |
| 全身立绘 `[C-FULL]` | 1024×1536 | **高 660**，宽按比例 | PNG 带 alpha | 档案栏立绘，与现有资产同高；`post.py --tier full` |
| 半身立绘 `[C-PORTRAIT]` | 1024×1024 | 不交付 | PNG | 只用于定风格、训 LoRA，游戏里不用 |
| 事件插图 `[C-SCENE]` | 1536×1024 | **1024×683** | WebP | 事件弹窗约 265×170 设计像素（2× 即 530×340），1024 宽留一倍余量给放大缩放 |
| 地图底图 `[C-MAP]` | — | 不交付 | — | 地图由引擎从 `cells.csv` 画矢量网格，不用图片底图 |
| 地形贴图 `[C-TILE]` | 1024×1024 | 暂不交付 | PNG | 地图目前是平涂 biome 色；将来做纹理层时再按 512 无缝出 |
| 聚落贴图 `I-01`～`I-05` | 1024×1024 | **256 / 224 / 200 / 168 / 136**（大都会→农庄） | PNG 带 alpha | 按档位缩小，让小聚落在地图上更小；`post.py --tier icon --size N` |
| 兴趣点图标 `I-22`～`I-46` | 1024×1024 | **64×64** | PNG 带 alpha | 地图上按 16 屏幕像素固定大小绘制（`map_marker_px`），映射在 `data/marker_art.csv` |
| 其他图标 `I-`（经济、宗教、防御） | 1024×1024 | 64×64 | PNG 带 alpha | 卡片和面板用；需要更大时再出 128 |
| 战术符号 `W-` | 1024×1024 | 64×64 | PNG 带 alpha | 中性色，引擎按势力染色 |
| UI 件 `U-` | 1024×1024 | 按件，设计尺寸 ×2 | PNG 带 alpha | 9-slice；现有 UI 是深色底 + 金色像素字，U- 系列是否采用另议 |

**去掉的条目**：地图瓦片 / PMTiles（不做 GIS，地图是矢量的）；图标"三档分别生成"（游戏只需要一档小尺寸，缩放由 `post.py` 做，铅笔纹在 64 px 下本来就看不到）；头像 512×512（游戏里是 96）。

### 10.8 三条会毁掉项目的做法

1. **绕过 `[S]` 直接写 prompt** —— 只要有人图省事自己编风格描述，那批资源就废了。把 `STYLE_CORE.txt` 设成唯一真相来源，代码里读取，不允许手抄。
2. **为每个势力单独生成一套彩色图标/箭头** —— 生成三次三种颜色，三次的笔触、纸纹、颗粒都会不同。必须生成中性版本，**用代码染色**。
3. **让 AI 画地图的地理形状** —— 见前一份地图架构文档。海岸线、河流、山脉必须来自 GIS 数据，AI 只上画风。

---

## 附录 A · `STYLE_CORE.txt` 完整内容（复制这一段存成文件）

v2（当前）：

```
clean colored pencil illustration on bright smooth cream paper, crisp confident
contour lines in dark umber pencil, light decorative directional hatching used
only for shading, fabrics rendered as smooth woven cloth with clean folds and
no fibrous or fuzzy texture, smooth evenly blended skin, every surface
fully coloured with solid local colour and soft shading, the same painted
treatment for buildings, objects and terrain as for people, no bare unpainted
linework, fresh and luminous, flat clean paper background with no grain and no aging, muted earthen
palette of raw umber, yellow ochre, burnt sienna, moss green, slate blue and
oxblood red, restrained color, warm diffuse overcast daylight, historically
accurate 12th to 14th century European material culture, naturalistic anatomy
and proportion, appealing idealised faces with fine features, youthful where
the age allows, contemporary character concept illustration quality, matte
finish
```


v1（2026-09-11 前的做旧版，仅存档）：

```
colored pencil illustration, hand-drawn on warm cream toned laid paper, visible
directional pencil hatching and cross-hatching, layered translucent pigment with
granular tooth texture, soft graphite underdrawing showing at contours, no ink
outlines, muted earthen palette of raw umber, yellow ochre, burnt sienna, moss
green, slate blue and oxblood red, desaturated and restrained color, warm diffuse
overcast daylight, historically accurate 12th to 14th century European material
culture, naturalistic anatomy and proportion, understated realism, antique
sketchbook plate quality, matte finish
```

### `STYLE_CORE_map_sepia.txt` —— 地图符号专用（2026-09-12）

只给 §6.9 的 `D-` 和任何用 `[C-MAPMARK]` 重出的 `I-` 用。人物、事件插图、UI 一律仍用上面的 v2。

```
hand-drawn pictorial map symbol in the manner of an illustrated storybook
atlas, monochrome sepia: one warm brown hue and nothing else, no other colour
anywhere, bold dark sepia ink contour of uneven hand-pressed weight drawn
freehand with a slightly wobbling line, the outline almost black-brown and
far darker than anything it encloses, strong contrast between that dark
outline and the pale tan tone filling the shapes, shaded only by fine
parallel hatching and short cross-hatching in the same dark ink on the side
away from the light, gently stylised and charming rather than technical,
massing simplified to a few bold shapes with its one characteristic feature
exaggerated, and nothing in the frame that the subject line did not ask for,
drawn in flat side elevation as a symbol cut out and
floating free with nothing whatsoever underneath it, not as a scale drawing,
no perspective recession, even flat lighting
with the shade thrown consistently to the lower right, historically accurate
12th to 14th century European material culture, heavy readable line weight
that still reads at thumbnail size, matte
```

### `STYLE_CORE_ui_vellum.txt` —— UI 部件专用（2026-09-12）

只给 §9 的 `U-` 用。v2 禁做旧、v1 做旧到没有剪影，两个都套不上一件"要被切成九宫格拉伸的羊皮纸部件"。

```
a single piece of manuscript furniture drawn as a clean game interface
element, cut from smooth vellum in a pale warm sand tone — a light
greyish tan, clearly warmer than paper white but never golden, never
yellow, never saturated — with an even unmarked surface, crisp confident contour and ruled lines in
dark raw umber ink of steady even weight — a greyed chocolate brown with no
red and no pink in it, brown rather than black, and no heavier than the
ornament it encloses — ornament rendered as fine flat
linework filled with a thin wash of raw umber and at most one verdigris or
oxblood accent, soft even shading only where a real edge is bevelled or a
real surface curls, straight true horizontal and vertical edges along
every run that will be stretched, and exactly repeating spacing along every
run of ornament, so the piece can be cut into a nine-slice without the
pattern tearing — an end that folds, rolls or is notched keeps its shape, the centre of any
panel left as plain unmarked cream vellum, historically accurate 12th to
14th century manuscript and leatherwork ornament, flat even frontal light,
clean and unaged, matte
```

## 附录 B · `NEGATIVE.txt` 完整内容

```
digital airbrush, glossy, smooth gradient, neon, oversaturated, high contrast,
anime, manga, cel shading, comic book, 3d render, cgi, plastic, vector art, flat
color fill, thick ink outline, oil painting impasto, watercolor bleed, photograph,
modern clothing, zipper, buttons on medieval garments, eyeglasses, wristwatch,
printed typography, lettering, watermark, signature, logo, lens flare, bokeh, HDR,
fisheye, extra fingers, deformed hands, plate armour before 1400, full gothic
plate, horned helmet, longsword crossguard anachronism, aged paper, foxing,
yellowed paper, heavy grain, smudged graphite, antique print, sepia, coarse
features, haggard, fuzzy fabric, fibrous texture, felted wool, furry cloth, bare line
drawing, unpainted sketch, outline only, pale washed-out, architectural line art
```

### `NEGATIVE_map_sepia.txt` —— 地图符号专用（2026-09-12）

**必须另立一份**：上面那份把 `sepia`、`aged paper`、`antique print` 全禁了，正是 `D-` 要的东西。这份改禁彩色、透视、地台和画框。

```
colour, full colour illustration, blue, green, red, saturated, polychrome,
multicoloured, colour photograph, digital airbrush, glossy, smooth gradient,
glow, neon, 3d render, cgi, isometric game asset, plastic, photograph,
photorealistic, anime, manga, cel shading, comic book, thick uniform vector
outline, heavy black ink, blotchy solid black fill, oil painting, watercolour
bleed, faint thin outline, pale washed-out line, low contrast, light grey
line, outline the same tone as the fill, perspective grid, vanishing point,
three-quarter overhead view, aerial view, landscape scene, horizon, sky,
background scenery, parchment background, paper texture background, ground
plate, base plinth, grass base, ground line, baseline, horizontal line
beneath the object, drop shadow, contact shadow, shadow cast on the ground,
decorative frame, border, vignette, printed typography, lettering, labels,
numerals, watermark, signature, logo, modern buildings, chimney stacks of
brick, plate glass, gothic plate armour before 1400, cluttered illegible
detail
```

### `NEGATIVE_ui_vellum.txt` —— UI 部件专用（2026-09-12）

三件事要禁：做旧和毛边（和 9-slice 打架）、镀金立体画框（样张里 `U-12` 被画成了一只 3D 金相框）、以及纸色背景（底色和部件同色就抠不出来）。

```
white, pure white, bleached, cold grey, bluish white, desaturated to
grey, colourless, golden, gold, amber, mustard, lemon, saturated yellow,
bright ochre field, orange, pink, rose, terracotta ink, red ink, aged paper, foxing, stains, yellowed with
damage, water damage, burnt edges, torn edges, deckled edge, irregular
hand-cut edge, ragged outline, crumpled, creased, heavy grain, fibrous
texture, thick black outline, heavy uniform outline, bold cartoon outline,
vector art, sticker, clip art, gilded picture frame, carved gilt wood,
ornate 3d moulding, polished metal, gold leaf shine, 3d render, cgi,
bevelled glass, perspective, vanishing point, tilted view, angled view,
isometric, drop shadow, cast shadow, glow, digital airbrush, smooth
gradient, neon, oversaturated, photograph, cream paper background,
parchment background, paper filling the frame, background the same colour as
the piece, scene, props, hands, furniture, desk, table, printed typography,
lettering, numerals, text, watermark, signature, logo, cluttered ornament,
asymmetrical ornament, the centre of the panel decorated
```

# 数据层架构需求文档 (Data Architecture Requirements)

**项目**：Our Grand Ages — 中世纪大战略游戏 (Godot 4.x / Steam)
**范围**：模拟状态的存储、调度、持久化与确定性
**版本**：v1.0 — 2026-09-11
**状态**：待评审 → 锁定

---

## 1. 目的与范围

本文定义游戏**模拟层数据架构**的强制性需求。它回答三个问题：

1. 规则内容（Defs）与运行时状态（State）如何分离、如何存储；
2. 每回合的计算如何调度，以满足性能预算；
3. 存档、多人同步、LLM 回放如何共用同一套机制。

**范围内**：省份/国家/角色/军队的状态存储、tick 调度、命令流、存档格式、确定性约束、遥测。
**范围外**：渲染、着色器、UI、美术管线、Azgaar 转换管线（已完成，作为 Defs 的上游生产者）、LLM prompt 工程。

**上游依据**：调研 Paradox (Clausewitz 脚本 + 内存 C++ struct)、Civ6 (SQLite 仅用于定义层，模拟层纯内存)、Total War (二进制 db table + 内存)。三家一致结论：**运行时不使用数据库**。本文将该模式落地到 Godot/GDScript。

---

## 2. 设计目标与非目标

### 2.1 目标 (按优先级)

| # | 目标 | 可验证方式 |
|---|---|---|
| G1 | **确定性**：同一存档 + 同一命令序列 → 逐位相同的状态 | 自动化回放测试，比对状态哈希 |
| G2 | **可演进性**：新增一列 CSV 数据不导致旧存档失效 | 存档兼容性测试套件 |
| G3 | **性能可预测**：tick 成本随省份数线性增长，无隐藏的 O(n²) | 基准测试 + 规模外推 |
| G4 | **低认知负担**：新增一个政策动作 ≤ 1 行 CSV + ≤ 1 个 handler 函数 | 代码审查 |
| G5 | **可分析性**：能对 AI 自对弈产出结构化数据用于平衡调优 | 遥测导出可被 SQL/pandas 查询 |

### 2.2 明确的非目标 (YAGNI 清单)

以下内容**当前阶段不做**，除非第 3 节的性能预算被实测突破：

- ❌ 引入完整 ECS 框架（Godot 的场景树 + 列式数组已足够，ECS 会增加大量样板）
- ❌ 运行时 SQLite / godot-sqlite（已在架构决策中否决，本文重申理由）
- ❌ 模拟主循环多线程化（确定性成本极高，收益在当前规模下为负）
- ❌ 用 C#/GDExtension 重写模拟层（仅在 R-4 优化后仍超预算时才考虑，见 §9.3）
- ❌ 网络状态同步（多人采用 lockstep 命令同步，见 R-6）
- ❌ 通用 mod API（先把 CSV 做干净，mod 支持是它的自然副产品）

> **复杂度原则**：本文的每一条需求都必须能说清「不做会付出什么代价」。做不到的条目应当删掉，而不是留着「以后可能有用」。

---

## 3. 规模假设与性能预算

### 3.1 规模假设 (Scalability Envelope)

| 实体 | 目标规模 | 设计上限 | 备注 |
|---|---|---|---|
| 省份 (Province) | 1,500 | 4,000 | 来自 Azgaar 管线；上限即架构必须无痛支撑的值 |
| 国家 (Nation) | 60 | 150 | 每个都跑 AI |
| 角色 (Character) | 800 活跃 | 3,000 | 含已故者的历史记录另计，不进热循环 |
| 军队堆栈 (Army) | 200 | 600 | 战时峰值 |
| 政策动作定义 | 76 | 300 | Defs，不随 tick 增长 |
| Trait 定义 | 41 | 200 | 同上 |
| 单局总 tick 数 | ~1,200 | 4,000 | 300 年 × 变粒度回合 |

### 3.2 性能预算 (Performance Budget)

目标硬件基线：**2019 年中端桌面 CPU（约 Intel i5-9400 / Ryzen 5 3600）单核**。

| 指标 | 目标值 | 硬上限 | 超限后果 |
|---|---|---|---|
| 单次经济 tick（全省份） | ≤ 8 ms | 16 ms | 超过一帧，必须跨帧摊销 |
| 单次 AI 决策轮（全部国家） | ≤ 120 ms | 400 ms | 需跨帧/后台线程 |
| LLM 意图解析（本地模型） | ≤ 1.5 s | 4 s | UI 必须有非阻塞反馈 |
| 存档写入 | ≤ 300 ms | 1 s | 自动存档不得卡顿 |
| 读档至可操作 | ≤ 1.5 s | 3 s | — |
| 存档体积（单个快照） | ≤ 5 MB | 20 MB | 影响云存档与备份轮转 |
| 模拟层常驻内存 | ≤ 120 MB | 300 MB | 不含贴图/音频 |
| 启动至主菜单 | ≤ 5 s | 8 s | Defs 加载是主要成本 |

### 3.3 一个关键的量化洞察

按 §3.1 上限做列式布局的内存估算：

```
4,000 省份 × 40 个数值字段 × 4 字节 = 640 KB
3,000 角色 × 60 个数值字段 × 4 字节 = 720 KB
——————————————————————————————————————
核心热状态总计 ≈ 1.5 MB
```

**结论：状态体积完全不是约束，CPU 才是。** 这直接决定了架构方向——不需要任何形式的分页、懒加载或外部存储；需要的是让这 1.5 MB 在 CPU cache 里跑得尽量快，并且**减少每 tick 触碰它的次数**（R-5 脏标记与分桶）。

这也是运行时数据库被否决的根本原因：为 1.5 MB 数据引入 SQL 查询计划开销，是纯粹的负收益。

---

## 4. 架构总览：三层模型

```
┌─────────────────────────────────────────────────────────────┐
│  DEFS（冷·只读）                                              │
│  policy_actions.csv / traits.csv / provinces.csv / ...        │
│  → 启动时加载并烘焙 → 常驻只读数组 + 字符串ID注册表              │
│  ❌ 不进存档                                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓ 只读引用（int 索引）
┌─────────────────────────────────────────────────────────────┐
│  COMMANDS（流·唯一写入口）                                     │
│  玩家输入 / LLM 解析 / AI 决策 → Command → 校验 → clamp        │
│  ✅ 全量写入 command_log                                       │
└─────────────────────────────────────────────────────────────┘
                            ↓ 唯一的变更通道
┌─────────────────────────────────────────────────────────────┐
│  STATE（热·可变）                                              │
│  PackedInt32Array / PackedFloat32Array 列式布局                │
│  ✅ 定期快照进存档                                              │
└─────────────────────────────────────────────────────────────┘
                            ↓ signal（不反向依赖）
┌─────────────────────────────────────────────────────────────┐
│  PRESENTATION  地图着色器 / UI / 叙述文本（LLM 生成，独立缓存）    │
└─────────────────────────────────────────────────────────────┘
```

**单向依赖**：Presentation → State → Defs。任何反向引用都是架构违规。

---

## 5. 需求条目

每条需求给出：需求描述、理由、**可扩展性影响 / 复杂度成本 / 性能影响**、验收标准。

---

### R-1 · Defs 与 State 物理隔离 `P0` `必须`

**需求**
建立两个 autoload：`Defs`（启动加载，加载完成后不可变）与 `Sim`（唯一持有可变状态）。任何可变游戏状态**禁止**存在于 Defs、节点属性或 `.tres` 实例中。

**理由**
Godot 的 Resource 默认是**缓存共享**的——`load()` 同一个 `.tres` 两次返回同一对象。若把可变状态放进 `.tres`，运行时修改会污染所有引用者，且在编辑器内可能写回磁盘。这是 Godot 项目最常见的隐蔽 bug 来源。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 存档只需序列化 `Sim`，新增 Defs 内容零存档成本 |
| 复杂度 | ⚠️ 低。约束是纪律性的，不增加代码量 |
| 性能 | ✅ Defs 可整体标记只读，避免防御性拷贝 |

**验收标准**
- `Defs` 中无任何在 `_ready()` 之后被写入的成员
- 存在一个 debug 断言：tick 结束时校验 Defs 的内容哈希未变
- `.tres` 仅用于美术/UI 资源，不用于规则数据

---

### R-2 · 稳定字符串 ID 注册表 `P0` `必须`

**需求**
所有 Defs 条目以**稳定字符串 key** 为主键（`"act_raise_levy"`、`"trait_ambitious"`、`"prov_calenmarch"`）。加载时构建 `String → int` 映射，运行时**只用 int 索引**。存档中**只写字符串 key**。

**理由**
Paradox 每次大版本更新炸旧存档，很大一部分源于数值 ID 漂移——在 CSV 中间插入一行，后面所有索引整体位移。字符串 key → int 的转换在加载时做一次（O(n) 哈希），运行时依然是 O(1) 数组索引，两头都不损失。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ **这是 G2（可演进性）的唯一支点**。CSV 可任意重排、插入、删除 |
| 复杂度 | ⚠️ 中。需要一个注册表 + 加载期校验 + 存档迁移路径 |
| 性能 | ✅ 运行时零成本；⚠️ 存档读写多一层映射（可忽略，见 R-8 实测项） |

**接口契约**

```gdscript
# res://sim/defs/def_registry.gd
class_name DefRegistry
extends RefCounted

var _key_to_id: Dictionary = {}      # String -> int
var _id_to_key: PackedStringArray = PackedStringArray()

func intern(key: String) -> int:
    if _key_to_id.has(key):
        return _key_to_id[key]
    var id: int = _id_to_key.size()
    _id_to_key.append(key)
    _key_to_id[key] = id
    return id

func id_of(key: String) -> int:
    return _key_to_id.get(key, -1)   # -1 = 未知，调用方必须处理

func key_of(id: int) -> String:
    return _id_to_key[id]
```

**验收标准**
- 在 `policy_actions.csv` 顶部插入 10 行新动作后，旧存档仍可正常读取且行为不变
- 加载期检测到重复 key 或悬空引用时，**启动即失败**并打印具体行号（fail fast，不静默降级）

---

### R-3 · CSV 为源格式，烘焙为运行时格式 `P1` `应当`

**需求**
CSV 保持为**唯一人工编辑源**（git 可 diff、可 mod）。增加一个烘焙步骤：CSV → 校验 → 输出单个二进制 blob（`FileAccess.store_var(data, false)`）。运行时只读 blob；仅在开发模式下允许直读 CSV 并打印耗时警告。

**理由**
GDScript 的 `String.to_float()` / `to_int()` 在数万单元格上是实打实的开销，且无类型校验——一个错字会静默变成 `0.0`。烘焙步骤把这两个问题一次性解决在构建期。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 内容量增长 10 倍不影响启动时间的量级 |
| 复杂度 | ⚠️ 中。需要一个构建脚本 + 「blob 是否比 CSV 旧」的检测逻辑 |
| 性能 | ✅ 启动时间预计从秒级降至百毫秒级，直接服务 §3.2 的 5s 启动预算 |

**实施要点**
- `full_objects=false`：禁止反序列化任意对象，避免存档/内容文件的代码执行风险
- blob 头部写入**源 CSV 的内容哈希**；不匹配则在 debug build 里自动重烘焙，在 release build 里报错
- 开发迭代阶段（P0）可跳过此项直读 CSV，但 R-1/R-2 的接口必须已就位，使烘焙成为纯粹的内部替换

**验收标准**
- 启动加载全部 Defs ≤ 300 ms（在 §3.1 上限规模下）
- CSV 中任一字段类型错误 → 烘焙期报错并指明 `文件:行:列`

---

### R-4 · 热状态采用列式布局 `P0` `必须`

**需求**
所有随 tick 变化的实体状态以 **Struct-of-Arrays** 存储，使用 `PackedInt32Array` / `PackedFloat32Array` / `PackedByteArray`，数组下标即实体 ID。**禁止**使用 `Array[Object]` 或 `Array[Dictionary]` 承载热状态。

**理由**
这与列式数据库 vs 行式的取舍是同一个道理，只是这里的单位是 CPU cache line 而非磁盘页。紧凑循环里 `PackedInt32Array` 是连续内存 + 直接索引；`Array[Dictionary]` 每次字段访问是一次哈希查找 + 一次指针跳转，且每个 Dictionary 是独立堆分配。

**坦率说明**：在目标规模（1,500 省 / 季度 tick）下，朴素写法大概率也不会卡。**这一条的优先级是「一开始就这么写，因为后期改的代价极高」，不是「现在必须优化」。** 一旦有 50 个系统在读 `province.population`，改成列式就是一次全库重构。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 4,000 省份时仍在预算内；行式布局约在 2,000 省开始劣化 |
| 复杂度 | ⚠️ **本文中最高的一项**。可读性不如对象模型，需要配套访问器和调试工具 |
| 性能 | ✅ 预计紧凑循环快 3–10 倍（GDScript 下，需实测确认） |

**复杂度缓解措施**（必须同时实施，否则本条净收益为负）：
1. 提供只读的「视图对象」用于 UI/调试：`Sim.province_view(pid)` 返回一个临时 RefCounted，聚合该省所有字段。UI 与叙述层用它，**只有 tick 循环用裸数组**。
2. 所有列的定义集中在一处，配套一个断言：所有列长度相同。
3. 编写一个编辑器插件或 debug overlay，能按 ID 转储单个实体的全部字段。

**参考实现**

```gdscript
# res://sim/state/province_state.gd
class_name ProvinceState
extends RefCounted

# —— 列（下标 = province_id）——
var owner_nation:  PackedInt32Array
var controller:    PackedInt32Array      # 战时占领方，与 owner 分离
var population:    PackedInt32Array
var development:   PackedInt32Array
var unrest_fp:     PackedInt32Array      # 定点数，×1000（见 R-7）
var terrain_def:   PackedInt32Array      # → Defs 索引，只读
var dirty:         PackedByteArray       # 位掩码：ECON=1, MIL=2, POP=4

const DIRTY_ECON: int = 1
const DIRTY_MIL:  int = 2
const DIRTY_POP:  int = 4

func resize(n: int) -> void:
    for arr: PackedInt32Array in [owner_nation, controller, population,
                                  development, unrest_fp, terrain_def]:
        arr.resize(n)
    dirty.resize(n)

func mark(pid: int, flags: int) -> void:
    dirty[pid] |= flags

func tick_economy(defs: Defs, bucket: int, bucket_count: int) -> void:
    var n: int = owner_nation.size()
    var i: int = bucket
    while i < n:
        if dirty[i] & DIRTY_ECON:
            var t: int = terrain_def[i]
            development[i] += defs.terrain_growth[t]
            dirty[i] &= ~DIRTY_ECON
        i += bucket_count
```

**验收标准**
- 4,000 省份的全量经济 tick ≤ 16 ms（在 §3.2 基线硬件上实测）
- 存在自动化基准测试，作为 CI 的一部分，回归超过 20% 即失败

---

### R-5 · 脏标记 + 分桶调度 `P1` `应当`

**需求**
每个实体持有脏标记位掩码。tick 只处理被标记的实体。对于必须周期性刷新的系统（人口自然增长、建筑进度），按 `entity_id % N` 分桶，每个 tick 只处理一桶。

**理由**
Paradox 的 modifier 系统本质是一堆加/乘法桶，只在 dirty 时重算。这把「每 tick 的成本」从「实体总数」解耦为「实际变化的实体数」，后者在和平期通常是前者的 5% 以下。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 成本随**活跃度**而非**总量**增长——这是支撑 4,000 省上限的关键 |
| 复杂度 | ⚠️ 中高。**漏标记 = 静默的逻辑 bug**，最难调试的一类问题 |
| 性能 | ✅ 和平期 tick 成本预计降低一个数量级 |

**复杂度缓解措施**（必须实施）：
- debug build 提供「全量模式」开关：忽略脏标记，全部重算，然后与增量结果比对。任何不一致即报错并指明实体 ID 与字段。这是**唯一可靠**的漏标记检测手段，必须在 P1 阶段与本需求同时上线。
- 分桶的桶数 `N` 必须是存档的一部分，否则回放不确定（见 R-7）。

**验收标准**
- 全量模式与增量模式跑 200 个 tick，最终状态哈希一致
- 和平期平均 tick 耗时 ≤ 战时的 20%

---

### R-6 · Command 作为唯一状态变更入口 `P0` `必须`

**需求**
任何对 State 的写入必须经由一个 `Command` 对象：

```
玩家输入 ─┐
LLM 解析 ─┼→ Command{type, actor_nation, params, issued_tick}
AI 决策  ─┘        ↓
              schema 校验 → 合法性检查 → 数值 clamp
                     ↓
            确定性引擎执行 → State 变更 + 追加 command_log
```

模拟系统内部**不得**直接互相写字段；跨系统影响通过发出新 Command 或在同一 tick 的后续阶段处理。

**理由**
这一条同时解决三个看似无关的问题，是本架构的最高杠杆点：

| 问题 | Command 如何解决 |
|---|---|
| **多人同步** | lockstep：网络只传命令，不传状态（Paradox 的做法）。带宽 O(玩家动作)，与地图规模无关 |
| **存档可复现** | 存档 = 种子 + 命令日志，重放即重建，LLM 一次都不用重调（项目既定目标） |
| **LLM 安全边界** | LLM 产出的 JSON 天然就是 Command。schema 校验 + clamp 是**唯一**的信任边界，只需在一处加固 |

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 新增动作 = 新增一个 handler，不触碰调度器（服务 G4） |
| 复杂度 | ⚠️ 中。需要命令注册表和分发；但它替换掉的是散落各处的直接写入，净复杂度接近持平 |
| 性能 | ⚠️ 轻微负担：每命令一次对象分配。命令数量级为每 tick 数十个，可忽略 |

**参考实现**

```gdscript
# res://sim/command/command.gd
class_name Command
extends RefCounted

var type_id: int          # → Defs 中的动作定义索引
var actor_nation: int
var params: Dictionary    # 已 clamp 的数值，key 为稳定字符串
var issued_tick: int

func to_log_entry() -> Dictionary:
    return {
        "t": Defs.actions.key_of(type_id),   # 存字符串 key，见 R-2
        "n": actor_nation,
        "p": params,
        "tick": issued_tick,
    }
```

**验收标准**
- 全文 grep：模拟系统之外无任何对 `ProvinceState` 列的直接赋值
- 任一命令的 params 被人为置为极端值（`1e9`、负数、NaN）后，clamp 后状态仍在合法域内，且不 crash

---

### R-7 · 确定性约束 `P0` `必须`

**需求**

| 约束 | 规则 |
|---|---|
| 数值 | 影响结果的量一律用**定点整数**。货币 ×100（分），比率/修正值 ×1000。浮点仅用于表现层 |
| RNG | 每个子系统一个独立的 `RandomNumberGenerator` 实例并各自 seed（`rng_combat`、`rng_event`、`rng_char`）。**禁用全局 `randi()`/`randf()`** |
| 迭代顺序 | 禁止迭代 `Dictionary` 后据此写状态（GDScript 的 Dictionary 保持插入序，但依赖它很脆弱）。必须按 int ID 升序遍历 |
| 并发 | 模拟主循环单线程。若使用 `WorkerThreadPool` 做只读评估（如 AI 打分），归约必须按确定顺序进行 |
| 时间 | 禁止在模拟层读取墙钟时间、帧率、`delta` |

**理由**
浮点非确定性在跨平台/跨编译器时真实存在（x87 与 SSE 的中间精度差异、FMA 合并、编译器重排）。Paradox 因此使用定点数。对本项目而言，非确定性会同时摧毁 lockstep 多人和存档回放——G1 是所有其他目标的前提。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 使跨平台多人成为可能，而非事后补救 |
| 复杂度 | ⚠️ 中。定点数运算需要辅助函数（乘除时的缩放处理），心智负担持续存在 |
| 性能 | ✅ 整数运算通常不慢于浮点 |

**验收标准**
- 同一初始种子 + 同一命令日志，在 Windows 和 Linux 上各跑 500 tick，最终状态哈希一致
- CI 中有一个 lint 规则，检测模拟层目录下的 `randi(`、`randf(`、`Time.`、`delta`

---

### R-8 · 存档格式：种子 + 快照 + 命令日志 `P1` `应当`

**需求**

```
save_v1.json                  # 清单：版本、内容哈希、世界种子、tick
├── snapshot_<tick>.bin       # 状态快照，store_var(full_objects=false)
└── command_log.jsonl         # 自上一快照以来的命令，每行一条
```

- 每 N 个 tick（建议 N=50）写一次快照，其间只追加命令日志
- 读档 = 载入最近快照 + 重放其后的命令
- 清单包含 `content_hash`：Defs 内容变更后，用它决定是走迁移路径还是拒绝加载

**理由**
既定架构决策是「JSON 存档」，这里做一个**有取舍说明的细化建议**：JSON 对清单和命令日志是理想的（人类可读、可 diff、易于调试和 bug 报告）；但对列式状态快照，JSON 会把 640 KB 的二进制数组膨胀到数 MB 文本并带来可观的 parse 开销。混合方案保留了 JSON 的全部调试优势，同时让快照保持紧凑。

若倾向于单文件纯 JSON，可折中为：JSON 外壳 + 各列以 base64 编码的 `PackedByteArray` 内嵌。体积略大于纯二进制，但仍远优于数字数组的文本化，且保持单文件。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 存档体积随**已玩时长**缓慢增长，而非随地图规模爆炸 |
| 复杂度 | ⚠️ 中高。快照 + 重放的组合需要仔细测试；迁移代码从第一天就要写 |
| 性能 | ✅ 自动存档只追加日志（≤ 1 ms）；完整快照仅每 N tick 一次 |

**验收标准**
- 在 §3.1 上限规模下，快照写入 ≤ 300 ms，体积 ≤ 5 MB
- 存档含 `version` 字段与至少一条已实现的迁移路径（哪怕是 v1→v2 的空迁移），从第一版起就存在

---

### R-9 · LLM 层与模拟层解耦 `P0` `必须`

**需求**
- **解析方向**：LLM 输出 → JSON schema 校验 → Command。校验失败则重试或降级到关键词解析，**绝不**部分执行
- **叙述方向**：模拟完成后，将结构化的 `TickResult` 传给叙述器。叙述文本存入**独立于状态的缓存**（`narration_<tick>.jsonl`）
- 状态重放时**不得**重新调用任何模型；叙述缓存缺失时显示模板化的降级文本

**理由**
这是既定的核心设计哲学（LLM 解析意图和叙述结果，但绝不拥有数值）的架构落地。把叙述文本从状态中剥离，意味着存档体积和重放速度不受叙述长度影响，也使叙述器可以随时更换模型而不影响存档兼容性。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 模型可替换、可离线、可按 tier 分配（本地解析 / 云端叙述） |
| 复杂度 | ⚠️ 低。schema 契约已存在，此处是边界纪律 |
| 性能 | ✅ 重放 500 tick 无任何模型调用，从分钟级降到秒级 |

**验收标准**
- 断网状态下读取任意存档并重放至任意 tick，状态完全正确（叙述显示降级文本）
- 注入一个畸形的 LLM 输出，系统拒绝执行且给出可读的用户提示，不 crash、不部分应用

---

### R-10 · AI 分层预算与执行调度 `P1` `应当`

**需求**
三层效用 AI（既定架构）各自受显式预算约束：

| 层 | 频率 | 预算 | 执行方式 |
|---|---|---|---|
| L1 战略（国家级目标） | 每 4–8 tick | ≤ 60 ms 全部国家 | 跨帧摊销，每帧一批国家 |
| L2 战役（省份/军队级） | 每 tick | ≤ 40 ms | 跨帧摊销 |
| L3 战术（即时反应） | 事件驱动 | ≤ 5 ms/事件 | 同帧 |
| LLM 批次（性格/外交润色） | 每 20–40 tick | 异步 | 后台，**结果不得影响数值** |

AI 评估阶段**只读** State；所有决策以 Command 形式提交，在统一的执行阶段按国家 ID 升序应用。

**理由**
AI 是本项目最可能突破性能预算的部分（60 国 × 1,500 省 × 76 动作 = 684 万次候选评估，若朴素实现）。必须靠候选剪枝（只评估相关省份）和跨帧摊销，而不是靠优化内循环。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ⚠️ **本架构中最大的扩展性风险点**，随国家数 × 省份数相乘增长 |
| 复杂度 | ⚠️ 高。跨帧状态机 + 候选剪枝 |
| 性能 | 关键路径。剪枝必须把候选集从 O(国家×省份) 降到 O(国家×边境省份) |

**验收标准**
- 60 国的完整 L1 决策轮 ≤ 120 ms，且可被中断/续跑
- 只读断言：AI 评估阶段结束时状态哈希未变

---

### R-11 · 遥测旁路（debug-only） `P2` `可选但强烈建议`

**需求**
`TelemetryLogger` autoload，仅在 debug build 启用。每 tick 追加关键指标到 `user://telemetry/run_<id>.csv`（或 SQLite），包含：各国 development/金库/人口分布、每个 policy action 的被选次数、faction 阶段停留时长、战争起止。

**理由**
Civ6 向 Cache 目录输出 `DebugGameplay.sqlite` 并非偶然。有了这个，平衡调优就从「凭感觉」变成数据驱动：跑 200 局 AI 自对弈，然后用 SQL/pandas 回答——76 个动作里哪些 AI 从不选（说明效用函数或成本设错了）？第 50 年时 development 分布是否过度集中？6 阶 faction 阶梯各阶段的实际停留时长分布如何？

对一个有 76 个动作 + 41 个 trait 的系统，这是从手工调参跨越到系统性平衡的唯一可行路径，且实现成本极低。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 内容量越大，收益越高 |
| 复杂度 | ⚠️ 低。纯追加写，无读路径，不与任何系统耦合 |
| 性能 | ⚠️ release build 中完全编译掉；debug 中 ≤ 1 ms/tick |

**验收标准**
- release 导出中不含遥测代码路径
- 提供一个无头自对弈模式：`godot --headless -- --sim-only --runs 200`，输出可直接被 pandas 读取

---

### R-12 · 模拟层与表现层隔离 `P0` `必须`

**需求**
模拟 tick 内**禁止**触碰任何 Node、贴图、着色器参数。tick 产出一个 `TickResult`（变更实体的 ID 列表 + 事件列表），由表现层订阅后按需刷新。地图着色器只在省份归属实际变更时更新调色板纹理。

**理由**
遵循 Godot 的「call down, signal up」原则，同时是无头自对弈（R-11）与自动化测试（R-7 验收）的前提——模拟层必须能在没有场景树的情况下运行。

| 维度 | 影响 |
|---|---|
| 可扩展性 | ✅ 使 headless 批量模拟成为可能 |
| 复杂度 | ⚠️ 低。一个事件总线 autoload |
| 性能 | ✅ 避免每 tick 的全量 UI 重建，这通常是此类游戏真正的帧率杀手 |

**验收标准**
- `godot --headless` 下运行 1,000 tick 无任何节点相关错误
- 一次省份易主只触发一次调色板纹理上传

---

## 6. 目录结构

按功能域组织（遵循 Godot 项目惯例），模拟层自成一个可独立测试的子树：

```
res://
├── sim/                          # ← 整个子树必须 headless 可运行
│   ├── defs/
│   │   ├── defs.gd               # autoload: 只读内容
│   │   ├── def_registry.gd       # R-2 字符串ID注册表
│   │   └── loaders/              # CSV → blob 烘焙 (R-3)
│   ├── state/
│   │   ├── sim.gd                # autoload: 唯一可变状态持有者
│   │   ├── province_state.gd     # R-4 列式
│   │   ├── nation_state.gd
│   │   ├── character_state.gd
│   │   └── army_state.gd
│   ├── command/
│   │   ├── command.gd            # R-6
│   │   ├── command_bus.gd        # 校验 / clamp / 分发
│   │   └── handlers/             # 每个动作域一个文件
│   ├── systems/                  # tick 阶段，按固定顺序执行
│   │   ├── economy_system.gd
│   │   ├── military_system.gd
│   │   ├── population_system.gd
│   │   └── faction_system.gd
│   ├── ai/                       # R-10 三层效用 AI
│   ├── determinism/
│   │   ├── fixed.gd              # 定点数辅助 (R-7)
│   │   └── rng_streams.gd
│   └── persistence/
│       ├── save_manager.gd       # R-8
│       └── migrations/
├── llm/                          # R-9 sidecar 客户端、schema、叙述缓存
├── presentation/                 # 地图、UI、着色器（只订阅，不写状态）
├── data/                         # CSV 源文件（Azgaar 管线产物）
├── tools/                        # 烘焙脚本、遥测导出、无头自对弈入口
└── tests/
    ├── test_determinism.gd       # R-7 验收
    ├── test_save_compat.gd       # R-2/R-8 验收
    └── bench_tick.gd             # R-4 基准，CI 门禁
```

**依赖规则（可用 CI 脚本静态检查）**：`sim/` 不得 import `presentation/` 或 `llm/`。

---

## 7. Tick 执行顺序（确定性契约）

每个 tick 严格按以下阶段执行，顺序不可变更（变更即构成存档破坏性改动，需要 bump 版本）：

```
1. 收集命令   玩家 + AI + 事件触发 → 按 (issued_tick, actor_nation, seq) 排序
2. 校验/clamp  schema + 合法性 + 数值域
3. 应用命令   按排序顺序逐条执行
4. 系统 tick   economy → population → military → faction → diplomacy（固定顺序）
5. 事件解算   条件检查 + 触发（使用 rng_event）
6. 产出       TickResult + 遥测行 + 叙述请求（异步）
7. 快照       若 tick % N == 0
```

---

## 8. 风险登记

| # | 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|---|
| RK-1 | R-5 漏标记导致静默逻辑错误 | 高 | 高 | 全量对拍模式必须与 R-5 同时上线，不可延后 |
| RK-2 | AI 评估突破预算 (R-10) | 中 | 高 | 先做候选剪枝，再考虑跨帧；两者都不够才谈线程化 |
| RK-3 | R-4 列式布局损害可读性，拖慢功能开发 | 中 | 中 | 视图对象 + 调试转储工具作为强制配套 |
| RK-4 | 定点数算术出现溢出/精度错误 | 中 | 中 | 集中在 `fixed.gd`，配套单元测试；debug build 开溢出断言 |
| RK-5 | GDScript 在 4,000 省规模下仍超预算 | 低 | 高 | 先完成 R-4/R-5 并实测；确认瓶颈后再评估局部 GDExtension（仅热循环，不重写全部） |
| RK-6 | 存档迁移债务累积 | 中 | 中 | 每次 Defs 破坏性变更必须附带迁移 + 测试用例，在 PR 模板中作为检查项 |

---

## 9. 实施阶段

### 9.1 P0 — 地基（在新增任何游戏系统之前完成）

> **理由**：这四条的共同点是——一旦有 10 个系统建立在错误的基础上，改动成本就是指数级的。它们必须先于内容开发。

- [ ] R-1 Defs/State 隔离（两个 autoload + 只读断言）
- [ ] R-2 字符串 ID 注册表 + 加载期校验
- [ ] R-4 列式 State（省份先行，其余实体跟进）+ 视图对象
- [ ] R-6 Command 总线 + 校验/clamp
- [ ] R-7 定点数模块 + RNG 分流 + lint 规则
- [ ] R-9 LLM 边界（schema 校验 → Command，叙述独立缓存）
- [ ] R-12 headless 可运行性 + 事件总线
- [ ] 基准测试骨架（`bench_tick.gd`）

### 9.2 P1 — 规模化

- [ ] R-3 CSV 烘焙管线
- [ ] R-5 脏标记 + 分桶（**含全量对拍模式**）
- [ ] R-8 快照 + 命令日志存档 + 首个迁移
- [ ] R-10 AI 预算与跨帧调度
- [ ] 跨平台确定性测试（R-7 验收）

### 9.3 P2 — 优化与分析（仅在预算被实测突破时触发）

- [ ] R-11 遥测 + 无头自对弈
- [ ] 热点 profile，识别真实瓶颈（**先测量，不臆测**）
- [ ] 条件触发项：局部 GDExtension / C# 重写 —— 仅当 profile 证明单个热循环占总耗时 > 40% 且已穷尽算法层优化

---

## 10. 评审检查清单

- [ ] §3 的规模假设是否与实际世界地图（Azgaar 产出的省份数）相符？如不符，重新推导预算
- [ ] R-4 的复杂度成本是否可接受？如不可，是否愿意接受 2,000 省的软上限以换取对象模型的可读性？
- [ ] R-8 的混合存档格式是否与既定的「JSON 存档」决策冲突？需明确取舍并更新架构决策记录
- [ ] P0 清单是否真的能在开始内容开发前完成？如不能，哪几条可以延后，延后的代价是什么？

---

## 11. 与现有代码库的映射与待决项（2026-09-14 补充）

本节由经济系统 spec（`docs/superpowers/specs/2026-09-14-economy-and-staging-design.md`）的对齐评审产生。文档写于 9 月 11 日，代码库从 8 月底起已按另一套结构生长，两者未曾对过。下面记录**已按本文执行的部分**、**名称映射**和**留给锁定评审的两项决定**。

### 11.1 目录映射（不改目录，改映射）

代码库不建 `sim/`，功能分层与 §6 一一对应：

| 本文 §6 | 代码库 | 说明 |
|---|---|---|
| `sim/defs/` | `scripts/engine/data_repository.gd` + `data/*.csv` + `data/maps/<id>/` | 启动加载、只读；CSV 直读（R-3 的烘焙为 P1） |
| `sim/state/` | `scripts/engine/game_state.gd` | 唯一可变状态持有者（见 11.3 第一项） |
| `sim/command/` | `scripts/engine/action_system.gd`、`order_pipeline.gd`、`order_costs.gd`、`world_ledger.gd` | 校验 / clamp / 执行；经济 spec 起加暂存列表与 `command_log` |
| `sim/systems/` | `scripts/engine/tick_engine.gd` 及其调用的各引擎类 | tick 阶段固定顺序 |
| `sim/determinism/` | `scripts/engine/rng.gd`（种子流）；定点整数在各引擎类内 | 无 `fixed.gd`，经济 spec 全程整数 |
| `sim/persistence/` | `scripts/engine/save_load.gd` | 单个 JSON（见 11.3 第二项） |
| `llm/` | `scripts/llm/` | 一致 |
| `presentation/` | `scripts/ui/`、`scenes/` | 一致 |
| `tests/bench_tick.gd` | `tools/bench_map.gd`、经济 spec 的 `tools/bench_economy.gd` | 基准工具，不入 CI 门禁 |

**§6 的依赖规则已做成测试**：`tests/engine/test_engine_isolation.gd` 扫描 `scripts/engine/` 下每个文件，非注释行不得出现 `scripts/ui/`、`scripts/llm/` 下任何 `class_name`，也不得引用 `Game` autoload。

### 11.2 规模假设按 manor 数读

§3.1 按"省份"做预算；本项目的细粒度实体是 **manor**（地图包每个陆地格一块）。beria 包：3 500 块 manor、203 省、684 镇、5 061 条镇产线、71 种货物。因此 §3.2 的经济 tick 预算（≤ 8 ms，硬上限 16 ms）按 manor 数对照，3 500 落在本文 1 500–4 000 的区间内。经济 spec 用按天分桶（30 天 = 桶数，天然入存档）把月底结算控制在预算内，并以 `bench_economy` 度量。

### 11.3 留给锁定评审的两项决定

1. **`GameState` 是否改为列式（R-4）**。现状：`metrics`、`world`、`manor_*` 等均为 Dictionary，四十余个引擎类按此读写。经济 spec 的做法：新增状态极小（两个整数、暂存列表、命令日志），**推导缓存用列式** `PackedInt32Array`（热循环所在），`GameState` 本体不动。建议：现阶段接受 §10 清单中"2 000 省软上限换可读性"的选项（实际规模为 203 省 / 3 500 manor），列式化 `GameState` 作为独立重构项目另行评估。
2. **存档是否拆成快照 + 命令日志（R-8）**。现状：CLAUDE.md 不变量 7"存档 = 一个 JSON"，无命令日志。经济 spec 的做法：提交时把每条 Command 追加进 `state.command_log`，随现有 JSON 保存，先把"可重放"的数据留下。建议：格式不动，待命令日志与确定性回放测试跑通后，再决定是否采用 §R-8 的折中方案（JSON 外壳 + base64 内嵌列数据，保持单文件）。

### 11.4 已按本文执行的项（经济 spec）

R-1、R-2、R-6（暂存即 Command，提交记日志）、R-7（整数金币、整数千分比复利、固定遍历顺序、无随机、无墙钟）、R-5（省级脏标记、30 天分桶、全量对拍开关 `economy_check_full`）、R-9（模型解析结果在暂存时落为数据）、R-12（引擎 RefCounted、顶栏只读缓存、隔离测试）。货币单位为**整金币**而非 ×100 定点：这是产品要求"无小数点"的设计决定，需要精度时改内部倍率、显示不变。

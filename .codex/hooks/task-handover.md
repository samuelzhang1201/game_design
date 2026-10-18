# One small step, one PR, one-to-one handoff

- 一个 session 只讨论并处理一个小问题／plan step；step 太大先拆小。不增加第二个 feature，不把后续步骤累积到当前 PR。
- 每个 step／PR 只有实施 session 和该 step 的唯一 `Review` session 全权负责，禁止第三个 session、子代理、协调者或嵌套 reviewer 参与。普通实施默认 Sol／low，审查保留 Sol／medium；复杂问题按 `.codex/harness.md` 说明原因后升级，不增加第三人。创建全新实施 session 时显式指定 `model="gpt-6.1-sol"`、`thinking="low"`，不假定子代理默认值会配置主会话，也不自动修改已运行会话。
- 顺序只有：实施 → 同一 PR 的 Review → CI 通过并合并 main → 下一个独立 step 的实施。Review 自行修复范围内问题并重跑相关检查，不广播回报、不再创建第二 reviewer。用户明确暂停时停止。
- handover 严格一对一：每个 session 最多一个前驱、一个全新后继；禁止 fork/resume、自环、回到旧 session、一对多、多对一和多对多。没有后续已授权任务就结束，不造空会话。
- 完成当前单元后先保存当前工作树内的精简 `HANDOVER.md`：授权／单一 scope、step／PR、两个负责人、checkout／branch／HEAD、拥有文件、未提交内容、检查与代码状态、现有进程、风险、下一任务／验收／停止条件。不得覆盖其他任务的检查点。
- `.superpowers/session-handovers/<source_session_id>.json` 保存 `source_session_id`、`status`（working/ready/handed_off）、`summary_path`、单个 `next_task`。同一 PR 的交接还记录 `step_id`、`pr_url`、`implementation_session_id`、`review_session_id`；确定了唯一 Review id 后再保存最终标记。普通无 PR 的任务可以省略这四项。
- `ready` 只表示当前单元完成并准备交接。调用一次 `create_thread`（禁止 fork/resume），提示只含检查点绝对路径、工作树绝对路径、一个下一任务、验收和停止条件。创建成功后写单个 `next_session_id` 和 `handed_off`，结束源 session。创建结果未知先核对已有目标，不盲目重试。
- 新 session 只读检查点、核对 diff 和必要指导／spec／plan 段落，不要重新读取全部历史，也不重做批准的计划。源 session 不等待、监督、反复唤醒或向完成的聊天群发消息。
- 交接保留检查命令、结果及对应 commit／输入 hash；输入未变时复用已通过检查，不因换 session 重跑。先收敛定向检查，再对冻结输入运行一次必要回归。状态更新只报告新发现、决策、阻塞、需用户处理的事或阶段变化，不逐项播报测试数量或重复报告等待。
- Stop hook 只校验显式标记，并把成功声明的边／PR 负责人对记入 Git common dir 的共享 registry，防止不同工作树的声明冲突；它不拦截所有会话创建工具，也不替代负责人的执行纪律。不读 transcript、不启动会话、不改变测试、模型、MCP、授权或信任。
- 没有原生 compact 能力就不声称已压缩；没有新会话工具则保留 ready 检查点并说明限制，不启动后台代理循环。

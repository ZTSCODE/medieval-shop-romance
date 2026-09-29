# 交互卡顿探针

在 Godot 启动参数中添加 `--profile-hitches`，正常游玩并重复拖牌、组合、打开记录页等操作。按 F9 将报告写入 `user://hitch-profile.json`；也可添加 `--hitch-report=绝对路径` 指定输出。探针默认关闭，不影响普通玩家。

报告的 `sections` 给出每类操作的次数、平均值、95 分位和最大耗时，`recent_hitches` 保留最近超过 16 毫秒的事件。`operation_match` 是组合规则匹配，`chapter_changed` 是章节状态刷新，`chapter_npc_presence` 是 NPC 出场判断，`sync_card_views` 是卡牌视图同步，`journal_refresh` 是记录页更新。正常游玩时 `frame_interval` 使用相邻实际帧的墙钟间隔；自动测试会同步推进剧情并等待资源，因此不记录这一项，以免把测试脚本停顿误判为游戏掉帧。

2026-09-24 的章节开窗流程中，优化前 `sync_card_views` 的 95 分位约 64 毫秒，`chapter_changed` 约 127 毫秒；优化后分别约 0.33 毫秒和 10 毫秒。此数据只覆盖测试路线及当时硬件，继续扩充卡牌数量后应重新采样。

同日对“合成中切换暂停”追加探针后，发现 Esc 会反复刷新四个存档槽并连锁刷新剧情 UI。修正后开窗流程的 `menu_pause_toggle` 最大约 1.77 毫秒，`time_pause_toggle` 最大约 0.04 毫秒。时间暂停时牌桌仍可拖放和即时交易，日期、顾客耐心、探索、配方、章节操作与对话准备停止；Esc 系统菜单仍冻结牌桌。

2026-09-24 进一步加入 `drag_start`、`drag_move`、`drag_finish`、`drag_cancel`、`drag_combination_hints`、`table_settle_overlaps` 和 `stack_combined_callback` 分段。30 张卡的原生开窗压力测试重复 10 次合叠/拆叠、10 次取消拖动，并实际触发一次主角+树配方；最终报告为 `work/card-drag-performance-visible-index-final-20260924/hitch-report.json`。按参与卡牌建立配方候选索引后，开窗测得 `drag_finish` 95 分位 2.24 毫秒、最大 6.55 毫秒，`drag_cancel` 95 分位 0.70 毫秒，`table_settle_overlaps` 95 分位 0.30 毫秒。无头复测见 `work/card-drag-performance-index-20260924/hitch-report.json`。这些段落计时不等同于 4K GPU 呈现时间。

同日对玩家指出的开场主角＋森林做真实拖拽与自动存档复测。此前压力测试直接在数据层合并森林且禁用了自动存档，漏掉组合后即时同步保存。开启自动存档的开窗基线中，组合与拆开后的采样帧分别最高约 158.7/165.5 毫秒；指针每次状态变化向五种系统形状重复注册，单次最高约 8.6 毫秒。现在画面指针保持原四态图片、点击粒子及文本框系统 I 字光标，自动存档用独立低优先级线程校验和原子写盘；同步退出/切换仍等待未完作业。最终 3840×2160 窗口（逻辑视口 1600×900）开窗报告在 `work/opening-save-4k-visible-20260924/hitch-report.json`：开场组合输入 1.16 毫秒、随后十二帧最长 8.89 毫秒；拆开输入 1.37 毫秒、随后最长 6.48 毫秒；自动存档主线程 0.40 毫秒。存档页打开 1.61 毫秒，保存/读取点击各约 0.45/0.17 毫秒；后台作业完成时仍观测到最长约 31.75/29.02 毫秒的单帧波动。损坏存档拒绝、覆盖备份与主菜单读取在 `tests/opening_save_hitch_suite.gd` 的隔离档中验证，故这些数据不代表极端满桌或慢盘保证值。

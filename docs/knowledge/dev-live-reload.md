# 边改边看的开发启动方式（2026-10-06）

用户要求：改完东西不想每次手动重启游戏。做法是给游戏加一个只在开发时用的启动参数 `--live`：双击 `tools/run_live.cmd`（等于 `Godot.exe --path <项目> -- --live`）。左上角会有一行小字 `LIVE   F5 restart   F9 replay opening`，正常启动的游戏里没有这些东西。文字和内容的修改不用重启：`localization/game.csv` 一保存，游戏直接从 CSV 重建中英文（不必先跑 Godot 导入）；`data/content.json`、`data/onboarding_goals.json` 一保存就重读，文件有错时保留原内容并在左上角说明原因。脚本（`.gd`）的修改必须重启才生效：按 **F5**，或由改代码的一方运行 `pwsh -File tools/live_restart.ps1`（往 `work/live/restart.flag` 写一下），游戏会先存档、自己重启、再自动回到刚才那趟旅程。**F9** 从取名之后重新开始开场（沿用现有名字、跳过动画），方便反复看开头的文字；它和“新旅程”一样会覆盖自动存档。

实现：`scripts/services/dev_live_reload.gd` 只负责盯文件和按键并发信号；`scripts/table_app.gd` 末尾的 `_live_*` 几个函数决定怎么接住变化；`ContentCatalog.reload_base()` 负责重读内容（章节模式启用了内容模块时不重读）。限制：正在读的剧情如果被改短到当前句不存在，对话会被收起；新增图片等资源、新增 `class_name` 仍要先跑一次 `Godot --headless --path . --import` 再重启；重读只换数据，不会回放已经发生过的事（比如已经上桌的卡不会因为改了位置而移动），要看开头就按 F9。验证：`tests/dev_live_reload_suite.gd`（无界面，核对从 CSV 重建的译文与导入结果逐条一致）。

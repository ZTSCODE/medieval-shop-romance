# 开场剧情的运行实现（2026-10-03）

开场剧本（`docs/story/opening-script-draft.md` v1.6）已接入游戏，作为临时内容。流程：五页序幕（自由城镇 → 白冬蔓延 → 开国者借运粮和长矛把城镇写上地图 → 称帝、白冬为帝国效力 → 地图边缘有人逃亡，找到了对抗白冬的线索）（全屏暗场，插画缓慢推近，文字在插画下方左对齐，整体居中，无标题无边框）→ 取名（`name_entry_page` 等于序幕页数：序幕读完后弹出，不能取消，取名期间时间暂停、按键全部交给输入框，名字定下前林边对话不开始）→ 林边那段对话：先是主角逃亡的几句旁白，再遇到信使（与其他对话同一个对话框，信使走出雾之前不显示立绘）→ 牌桌出现“你”和黑刺李林 → 拖到林子上探索 8 秒 → 信使追上来，出现黑刺李果 → 拖到信使身上听他讲刺林的规矩 → 信使跑开，留下獾道 → 拖到獾道上走 6 秒 → 獾道变成立石。新手目标第一阶段“走进雾里”共三项，全部完成后接原有的两个阶段。

数据在 `data/content.json`，由 `tools/content/build_opening.py` 生成（同时写 `localization/game.csv` 的中英文；改台词就改这个脚本再运行，然后 `Godot --headless --path . --import`，否则游戏里显示键名、新的全局类名也不被识别）。开场配置：`page_layouts`（`{"style": "chronicle", "art": 路径}` 的页用全屏序幕，由 `scripts/ui/chronicle_view.gd` 呈现，序幕期间收起右侧栏）、`name_entry_page`、`prologue_story_id`、`tutorials`（提示依次让位，条件有 `until_stage`、`until_story`、`until_kind_gone`）。剧情：`scene: true`（人物尚未上桌，不要求牌桌上有对话双方，不能带牌桌后果）、`npc_hidden_until`、旁白、选项（只改措辞不改后果，分支随存档，旧的 5 字段对话存档仍可读）。同一人物的多段剧情按 `story_ids` 顺序和 `requires_completed` 依次触发。离场事件可 `leave_cards`。

**通用地点探索**（`scripts/model/location_exploration.gd`，唯一入口 `advance()`）：“你”与一张定义了 `explore: {duration, consumes, outputs}` 的地点卡单独成叠时计时，进度条复用牌桌的工作进度行，到时先在副本上验证再产出，并上报 `explore_completed:<卡牌ID>`。开场那次探索结束后才接手；章节模式不启用。半路进度不入档，读档或新旅程后从零开始。进村以后的地点都可以直接用这套定义。

存档方面的修复：读档时卡牌类别取自内容目录（不再依赖旧版写死的种类表）；“开场未激活时必须有商店卡”只在内容定义了商店卡时检查；序章对话开始时就把信使记入人物关系。

验证：`tests/opening_story_suite.gd`（无界面，55 项，含三处存档往返和獾道探索）与 `tests/opening_story_capture.gd`（实机走查，截图在 `outputs/opening-story/`）。截图一律用 `pwsh -File tools/run_hidden_capture.ps1 tests/opening_story_capture.gd` 后台运行：--headless 不渲染，所以用隐藏且放在屏幕外的窗口。三个审计“空内容基座”的旧测试改为先换成空目录再测；`opening_ui_suite` 改为用固定四页数据只测底部文字框，仍有 7 项改动前就存在的失败；`brown_pause_dialogue_suite` 的 3 项失败也是原有的（对话框由另一处在改）。美术全是临时素材：信使用用户在 Obsidian 卡牌角色白板选定的原图；主角以它为风格参考生成（右手疑似画了戒指，待重画）；五张序幕插画为粗墨线、黑青金配色；四张地点/资源卡面为暗调水粉风格。原图在 `outputs/opening-art/`。

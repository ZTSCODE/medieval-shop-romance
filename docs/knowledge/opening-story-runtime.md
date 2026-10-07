# 开场剧情的运行实现（2026-10-03）

开场剧本（`docs/story/opening-script-draft.md` v1.6）已接入游戏，作为临时内容。流程：五页序幕（自由城镇 → 白冬蔓延 → 开国者借运粮和长矛把城镇写上地图 → 称帝、白冬为帝国效力 → 地图边缘有人逃亡，找到了对抗白冬的线索）（全屏暗场，插画缓慢推近，文字在插画下方左对齐，整体居中，无标题无边框）→ 取名（`name_entry_page` 等于序幕页数：序幕读完后弹出，不能取消，取名期间时间暂停、按键全部交给输入框，名字定下前林边对话不开始）→ 林边那段对话：先是主角逃亡的几句旁白，再遇到信使（与其他对话同一个对话框，信使走出雾之前不显示立绘）→ 牌桌出现“你”和黑刺李林 → 拖到林子上探索 8 秒 → 信使追上来，出现黑刺李果 → 拖到信使身上听他讲刺林的规矩 → 信使跑开，留下獾道 → 拖到獾道上走 6 秒 → 獾道变成立石。新手目标第一阶段“走进雾里”共三项，全部完成后接原有的两个阶段。

数据在 `data/content.json`，由 `tools/content/build_opening.py` 生成（同时写 `localization/game.csv` 的中英文；改台词就改这个脚本再运行，然后 `Godot --headless --path . --import`，否则游戏里显示键名、新的全局类名也不被识别）。开场配置：`page_layouts`（`{"style": "chronicle", "art": 路径}` 的页用全屏序幕，由 `scripts/ui/chronicle_view.gd` 呈现，序幕期间收起右侧栏）、`name_entry_page`、`prologue_story_id`、`tutorials`（提示依次让位，条件有 `until_stage`、`until_story`、`until_kind_gone`）。剧情：`scene: true`（人物尚未上桌，不要求牌桌上有对话双方，不能带牌桌后果）、`npc_hidden_until`、旁白、选项（只改措辞不改后果，分支随存档，旧的 5 字段对话存档仍可读）。同一人物的多段剧情按 `story_ids` 顺序和 `requires_completed` 依次触发。离场事件可 `leave_cards`。

**通用地点探索**（`scripts/model/location_exploration.gd`，唯一入口 `advance()`）：“你”与一张定义了 `explore: {duration, consumes, outputs}` 的地点卡单独成叠时计时，进度条复用牌桌的工作进度行，到时先在副本上验证再产出，并上报 `explore_completed:<卡牌ID>`。开场那次探索结束后才接手；章节模式不启用。半路进度不入档，读档或新旅程后从零开始。进村以后的地点都可以直接用这套定义。

存档方面的修复：读档时卡牌类别取自内容目录（不再依赖旧版写死的种类表）；“开场未激活时必须有商店卡”只在内容定义了商店卡时检查；序章对话开始时就把信使记入人物关系。

验证：`tests/opening_story_suite.gd`（无界面，55 项，含三处存档往返和獾道探索）与 `tests/opening_story_capture.gd`（实机走查，截图在 `outputs/opening-story/`）。截图一律用 `pwsh -File tools/run_hidden_capture.ps1 tests/opening_story_capture.gd` 后台运行：--headless 不渲染，所以用隐藏且放在屏幕外的窗口。三个审计“空内容基座”的旧测试改为先换成空目录再测；`opening_ui_suite` 改为用固定四页数据只测底部文字框，仍有 7 项改动前就存在的失败；`brown_pause_dialogue_suite` 的 3 项失败也是原有的（对话框由另一处在改）。美术全是临时素材：信使用用户在 Obsidian 卡牌角色白板选定的原图；主角以它为风格参考生成（右手疑似画了戒指，待重画）；五张序幕插画为粗墨线、黑青金配色；四张地点/资源卡面为暗调水粉风格。原图在 `outputs/opening-art/`。

## 2026-10-06：开场之后先是主角的独白（覆盖上文的流程顺序）

用户定的新顺序：开场动画 → 取名 → **主角一个人在雪开始消散的地方自言自语**（牌桌上只有“你”）→ 说完后黑刺李林作为第一张卡从屏幕右边滑上桌 → 主角对着林子犹豫（“要不要试一试？”）→ 新手目标第一阶段“熟悉你的桌面”：拖动桌面、缩放、把“你”拖到黑刺李林上 → 探索 8 秒，林子消失 → **林中遇到信使**那场戏自己开始（人还没上桌）→ 读完后信使和黑刺李果上桌 → 之后同上文（讲规矩、獾道、立石）。主角的过去和他带着什么是他心里的秘密，开头不讲（见 story-premise.md）。

实现上新增了三样通用的东西。**独白**：剧情写 `"solo": true`、`"npc_id": ""`，只能有主角和旁白的台词，不属于任何人物、不进手账、不能带牌桌后果，每段只播一次；入口是 `DialogueFlow.start_solo(id)`，对话框文件没有改（没有对面的人时它本来就只显示主角立绘）。**自己开始的剧情**：`opening.scenes` 按顺序列出（可带 `stage`，如 `"complete"` 表示要等林子走完），由 `table_app._next_opening_scene()` 决定下一段，取代原来的 `prologue_story_id`；两段之间若有新卡上桌，会等卡落定再开始，这段空档里不显示提示和目标栏。**剧情读完才上桌的卡**：`opening.arrivals`（`kind`、`after_story`，可带相对主角卡的 `offset` 和 `metadata`），唯一入口 `OpeningFlow.deliver_arrivals(story_id)`，只在剧情读完的那一刻调用，先在副本上验证；开场未完成时存档允许这些卡还没到。提示多了一个条件 `after_story`。开局的卡现在放在开场镜头正对的桌面中央（以前在整张桌子中央，落在屏幕下缘之外）。

内容仍由 `tools/content/build_opening.py` 生成，已重新对齐现有卡面，并原样保留开场动画的配置（`opening.film` 归 `build_opening_film.py` 管），可以放心重新运行。新手目标的阶段顺序在 `data/onboarding_goals.json`。验证：`tests/opening_story_suite.gd`（80 项）、`tests/opening_story_capture.gd`（截图在 `outputs/opening-story/`）、`tests/onboarding_goal_panel_capture.gd`（已改为先走过序幕和独白）。已知的小问题，都不是这次引入的：英文卡名“Blackthorn Wood”在卡面上被截断；独白最后一句的按钮仍写“结束交谈”；牌桌上没有雪的画面，雪只在台词里。旧的开场中途存档（独白加入之前存的）读不回来，需要开新旅程。

## 2026-10-06 晚：种子卡、信使来了又走、溪边小道与背风地（覆盖上一节里信使之后的部分）

用户定的新流程：开局桌上是“你”和**那一把种子**（主角偷的种子，卡 `card.res.winter_seed`，从头到尾都在桌上，开场里不解释它）→ 独白 → 黑刺李林上桌 → 犹豫 → 新手目标（多了一项“左键拖动单张卡牌，右键拖动整个组合”，拖起一张卡即完成）→ 走进林子，林子用掉，**信使卡和溪边小道卡**出现 → 把“你”拖到信使身上才开始相遇那场戏，说完**信使卡离桌**（去送信）→ 把“你”拖到溪边小道上走 6 秒，**信使卡回来，背风地卡出现** → 再拖到信使身上：他介绍背风地、两人互通姓名（信使暂名奥辛 / Oisín），说完他留在桌上。黑刺李果、獾道、立石都已删除（卡、文字、目标、提示；图片文件还在 `assets/art/cards/painted_20261004/`，不再引用）。

为此加的三个通用小机制：离场事件可以写 `"returns": true`，表示人只是暂时走开（卡离桌），不算“已经离开”，之后同一个人物的卡再上桌可以接着讲下一段；地点卡的 `explore` 可以写 `"blocked_by": [卡种类]`，桌上还有这些卡时不能探索（溪边小道要等信使走了才能走）；牌桌在玩家拖起卡时发 `card_dragged(whole)` 信号，左键拖起（不是整叠）时上报新手目标事件 `card_dragged`。三张新卡面按完整纸卡合集画法生成，原图、提示词和切图在 `outputs/card-seed-stream-lee-20261006/`（同一张图里还有烧炭窑、水井、麦田等九张备用卡面，未接入）。英文卡名受卡面标题宽度限制，取了短的：A Handful、Brookside。验证：`tests/opening_story_suite.gd`（100 项）、`tests/opening_story_capture.gd`、`tests/onboarding_goal_panel_capture.gd`。这次改了剧情结构，文案审核器的旧快照对不上新文字，需要在审核器那边重新载入源工程。

**删改内容后必须换存档标记（2026-10-06 出过事故）：** 存档按 `data/content.json` 的 `content_generation` 分目录存放（`saves/<标记>/`），存储服务不会覆盖一份它读不懂的存档。这次删掉黑刺李果等卡后没有换标记，旧的自动存档里还有这些卡，于是读不出来、也不许覆盖，结果“新旅程”和 F9 都存不了档，卡在存档页。现在标记已改为 `opening_20261006`（在 `tools/content/build_opening.py` 里，旁边有说明）：以后只要删掉或改名了卡牌、剧情、事件，就换一个新标记，旧存档留在旧目录里不动。这条路径由 `tests/new_journey_save_capture.gd` 检查（别的走查脚本都把存档换成了空操作，查不到这类问题）。

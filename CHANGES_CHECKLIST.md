# 改动核对

## 2026-10-05

- 开场动画接入游戏：新旅程的五页文字序幕改为播放开场 PV（v7），带中英字幕（走本地化表）和“跳过”按钮，播完或跳过后照常取名；五页序幕保留为后备。涉及 `scripts/ui/opening_film_view.gd`（新）、`scripts/ui/opening_overlay.gd`、`scripts/model/opening_flow.gd`、`scripts/table_app.gd`（一行连接）、`data/content.json` 的 `opening.film`、`localization/game.csv` 的 38 行、`assets/video/opening/opening_film.ogv`、`tools/content/build_opening_film.py`、两个新测试；说明见 `docs/knowledge/opening-film-in-game.md`。风险：视频 432 MB（本机编码器的问题只能全关键帧），发布前须重压；没有人听过游戏里的声音；`tools/content/build_opening.py` 已落后于 `content.json`，运行会冲掉别处的改动。

## 2026-10-04

- 用户否决 v9（“这个版本不太行，暂时先用上一个版本”）：`outputs/opening-cg-film/final/` 已恢复为 v7（合成配乐 `score_v7.wav`、无新增镜头、3 分 07 秒），v9 成片移到 `final/v9_not_used/`；两个暗示秘密的新镜头 `p_f01_a`、`p_f02_a` 仍在 `clips/`，未用。用户接着在问改用 AI 生成音乐（Suno、ElevenLabs）并让画面跟音乐走的可行性。
- 开场 PV v9（已被否决，3 分 13 秒）：配乐重写为全片一支曲子、一个节奏型、一套和弦循环，并改用录音采样乐器渲染（`scripts/score_sampled.py`，库在 `D:\MusicLibraries`）；粮仓之后新增两个镜头暗示地下封存着秘密（封印铁门、石台上的铁匣），结尾空石台与之呼应；文件覆盖 `outputs/opening-cg-film/final/`。风险：新镜头未经用户事先审图；免费采样库奏法少，快速重复音可能机械；REAPER 与 Splice 尚未真正接入渲染；仍无人试听。
- 开场 PV v7（只改配乐）：把 1:51 那一秒的钟、铜管长和弦与弦乐音型作为小节单元，重复铺满城破之后的整段旁白（1:53–2:31），不再中断；最终文件固定为 `outputs/opening-cg-film/final/opening_pv.mp4`（字幕版）与 `opening_pv_no_captions.mp4`，配乐 `audio/score/score_v7.wav`。旁白在混音中的可识别率 97.0%，仍无人试听。
- 开场 PV v6（只改配乐）：按用户意见，城破之后整段帝国旁白改为不间断的重击鼓点强节奏，地窖段回归安静只留风声，戒严段一开始就是全力；成片 `outputs/opening-cg-film/edit/pv_v6_subs.mp4`、母版 `pv_v6.mp4`，配乐 `audio/score/score_v6.wav`（脚本改名为 `scripts/score_pv.py`）。风险同下：纯合成音色、无人试听，旁白在混音中的可识别率 97.3%。
- 开场 PV v5（画面与 v4.2 完全相同，只换声音）：配乐改为代码合成的原创曲（`outputs/opening-cg-film/scripts/synth.py`、`score_v5.py`，输出 `audio/score/score_v5.wav`），按剪辑表的段落与拍点写成；旁白改用 MiniMax speech-2.8-hd 整句朗读后切分（`mm_tts.py`、`v5_vo.py`），做了年长女声与男声说书人两套；成片 `outputs/opening-cg-film/edit/pv_v5_wiselady_subs.mp4`、`pv_v5_storyteller_subs.mp4` 及无字幕母版；说明见 `docs/knowledge/opening-pv-score-and-narration.md`。风险：配乐是纯合成音色的第一版，没有人实际听过，只做了响度、频段、拍点和语音识别核对；片中仍有网上找来的风声、战场、剑、钟声等临时音效；API key 未写入项目，重录需用户再次提供。

## 2026-10-03

- 开场 PV v4.2 成片（960p 验证版，3 分 07 秒，115 个新镜头，讲帝国借白冬统治的故事，主角不出场）：`outputs/opening-cg-film/edit/pv_v4_subs.mp4`（中英字幕）、`pv_v4.mp4`（母版）、审片页 `outputs/opening-cg-film/index_v4.html`，分镜 `docs/story/opening-cg-film-v4-storyboard.md`；风险：按用户睡前指示未经他审图直接出片，临时配乐取自《巫师3》《战神》原声、音效来自网络，仅供审片必须替换；声音只做了数值核对没有人工试听；尚未接入游戏，现有五页序幕不变。

- 新增开场 CG 动画 960p 验证片（`outputs/opening-cg-film/`，剧本分镜 `docs/story/opening-cg-film.md`）：参考绝对魔权与哈迪斯2 预告片的叙事方法重写开场，33 镜、69.9 秒，本机 MiniMax H3 生成画面、音效与旁白，临时配乐为 CC BY 曲目；未接入游戏，现有五页序幕不变。风险：声音只做了数值核对没有人工试听；片中把“霜里发芽的旧种粮”和“主角曾是奉命烧粮的人”这两个待确认提案画了出来，需用户确认；配乐需署名且正式版要替换。

## 2026-10-02

- 修正主菜单、通用按钮与金边在 HDR 2D 下的手绘配色色彩空间，按概念图分别标定按钮纸亮度并截图验证；风险：不同显示器观感仍需确认，本次不重构旧纸肤及 3D 材质。

## 2026-10-01

- 接通主视口、卡牌及棋盘子视口 HDR 2D，选中及落点金边使用封顶的 HDR 高光；风险：浮点绘制增加显存开销，材质颜色与实际屏幕观感仍需验收。隔离截图及 EXR 在 outputs/hdr-pipeline-20261001。

- 卡牌商店桌面切换 Forward+ / D3D12，保留配置备份并通过 180 帧图形启动检查；风险：材质、灯光与 HDR 观感需复核，旧运行进程须重启。

# 粉色模块纸张与逐帧舒展

## 选定来源与范围

用户于 2026-09-18 选定 `outputs/ui-exploration-v7/parchment-rose-aligned.png`。接入卡牌、底部序章/对话纸、独立姓名纸条和继续按钮。人物原图与身份不变；其他窗口继续使用已有美术。

## 静态组件

生产目录：`assets/art/ui/rose_modular/`。

| 文件 | 用途 |
| --- | --- |
| `paper_tile.png` | 主纸面，固定密度镜像重复 |
| `back_tile.png` | 玫瑰底纸，独立生成 |
| `paper_border.png` | 主纸的角部与四边，中央透明 |
| `slip_border.png` | 姓名纸条与按钮的独立纸边 |
| `layout.json` | 源图区域、角部范围、固定边厚、纸层位置、平铺尺度 |
| `components.source.json` | 完整提示词、参考角色、生成原始路径、尺寸与哈希 |

以上四张均分别使用内置图像生成工具制作，没有将概念整图切成一个可拉伸背景。内置工具没有暴露模型/质量档参数，来源记录不虚构该设置。

完整提示词与来源：[静态组件](C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/rose_modular/components.source.json)、[卡牌逐帧](C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/rose_modular/unfold_card/manifest.json)、[对话逐帧](C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/rose_modular/unfold_dialogue/manifest.json)。

`RosePaperStyle` 将纸面、底纸、边条和角部各自绘制。放大界面会增加重复次数；最后不足一块的边条裁切源区，不压缩角部。镜像交替重复使相邻块共享接缝像素，避免普通直接重复造成色彩断层。内部另有完全不透明底层，角色 PNG 的透明区露出纸面。

## 独立绘制动画

- `unfold_card/frame_00.png` 到 `frame_08.png`：9 张、1024×1536。
- `unfold_dialogue/frame_00.png` 到 `frame_08.png`：9 张、1774×887。
- 首尾先生成，再生成中点与区间中点；每次生成仅一个时刻。采用与未采用尝试均在各自 manifest 中登记。
- 运行时 14 帧/秒。保留同一画布、锚点和等比缩放；不同帧不按各自包围盒重新对齐。
- 动画不使用视频抽帧、程序变形、补间图像或淡入替代。绘制帧展示折面、纸张反面与边缘打开。
- 原始 PNG 的纸面略带 alpha。运行时 shader 补齐近不透明纸面，并清除极低 alpha 的外部杂点；不改源图 RGB、不把透明背景变成实心矩形。

首次显示序章或 NPC 对话时播放纸张舒展；翻页/换句不重播。点击展开中的纸张先完成展开，不顺便跳过剧情。新产物从原来源飞出时播放卡牌舒展，普通拖放不重播。Esc 暂停当前帧；读档保存剧情状态，不保存或重演一次性动画状态。

## 验证入口

- `tests/rose_paper_geometry_suite.gd`：固定边厚、平铺密度、末块裁切、透明外角与不透明内场。
- `tests/rose_ui_runtime_suite.gd`：原生图像与完整取名、探索、对话、暂停、读档、信使离场流程；使用 `--flow-qa --qa-dir=...` 的隔离存档。
- `tests/flat_image_geometry_suite.gd`：保留头像、插画、图标、进度等比例检查，并迁移新纸张动画检查。
- `work/rose-native/`：原生截图、逐帧运行截图及检查日志。

本轮不打包。技术检查通过与用户对笔触、纸边、展开节奏的视觉接受分别记录。

## 本轮结果

- 原生运行：60 项通过；重新启动后读档：4 项通过，错误日志为空。
- 图像与动画几何：802 项通过；模块纸层：92 项通过；瘦卡交互：48 项通过。
- 内容与本地化：1659 项通过；存档快照：121 项通过。
- 原生截图检查了两种语言、960×640 与1680×720窗口，纸张不拉伸，字幕、立绘和右下 HUD 分开显示。
- 两种高反差背景下逐像素比对，静态卡底及展开起/中/尾帧的纸面不透背景，外部无可见棕色晕光。
- 修正了姓名条自动换行造成的高度膨胀；前纸与底纸分别内缩，使展开末帧与静态纸叠保持一致外部尺寸。
- 保留信使原始图、已选概念图与旧可执行文件的原哈希；测试进度仅写入 `work/rose-native/profile`。

交付预览位于 `outputs/rose-ui-review/`：实机对话、卡牌全览、不同尺寸组件、逐帧舒展 GIF。GIF 直接编码 Godot 每帧绘制截图，不插入变形或补间帧。视觉接受仍由用户看预览后决定。

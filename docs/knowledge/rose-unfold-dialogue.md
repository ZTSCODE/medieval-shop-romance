# 粉色对话纸张舒展动画

## 交付范围

本组交付 9 张逐帧独立绘制的纸张舒展 PNG，用于用户已选择的粉色对话界面。内容仅包括浅粉玫瑰奶白主纸与紧凑底纸，不含姓名条、文字、按钮、人物或背景。

- 素材目录：`assets/art/ui/rose_modular/unfold_dialogue/`
- 播放顺序：`frame_00.png` → `frame_08.png`
- 完整逐帧提示词、输入参考、原始生成文件、SHA-256 和 alpha 检查：同目录 `manifest.json`
- 只读检查工具：`work/rose-unfold-dialogue/inspect_frames.py`，没有留在美术资产目录。
- 本线没有改游戏代码、全局布局、AGENTS、改动列表或存档，没有打包。

## 锁定参考与生成方法

唯一获准的视觉源是 `outputs/ui-exploration-v7/parchment-rose-aligned.png`，已实际查看。SHA-256：`8226AEFBE1BDAEBBF750512DAC7E4A2806347F0BDF72B5887E034A239D24D200`。

使用内置 image_gen，每次调用只生成一个时刻。先完成 08 终帧，再画 00 首帧，依次补 04、02/06、01/03/05/07；每个中间时刻均给出其两侧已完成的参考帧。重绘时同样保留对应的前后姿态参考。

内置工具没有开放 model 或 quality 选择，未填写虚构的高质量参数。共调用 17 次，保留 9 帧，其余 8 次尝试的原始文件和提示词同样记入清单。所有原始生成文件留存于生成工具的默认目录。

没有从视频抽帧，没有程序变形、插帧或合成帧，没有修改 PNG 像素，没有逐帧裁切或缩放。下面的裁剪区是共同元数据，便于播放器统一取图。

## 画幅与播放器接口

```json
{
  "canvas_size": [1774, 887],
  "final_bounds": [104, 282, 1569, 325],
  "common_crop": [102, 248, 1573, 385],
  "fps": 14,
  "frame_count": 9
}
```

实际工具输出为 1774 × 887，后续所有帧均保持相同画幅。原提示希望约 4.5:1 的纸体，终帧实际主体约 4.83:1，已将真实尺寸交给主流程。

`final_bounds` 是第 08 帧的主纸面范围。播放器应按它映射目标纸身，所有完整 PNG 共享同一个等比缩放和位置，不能按每帧包围框分别拉伸。

`body_union` 为九帧中 alpha ≥ 16 的最大八连通纸面主体范围并集 `[104,250,1569,381]`。向外保留 2 像素后，得到统一 `common_crop`。alpha 极低的外部散点单独记在 `bbox_alpha_nonzero`，没有拿它们撑大公共纸面区域，也没有编辑掉它们。

## 逐帧检查

| 帧 | alpha ≥ 16 的主体范围 x, y, w, h | 中心 alpha | SHA-256 前缀 |
| --- | --- | --- | --- |
| 00 | 711, 250, 352, 381 | 253 | 690FAB0C40417A74… |
| 01 | 637, 257, 500, 357 | 254 | 1F66B10B4516247F… |
| 02 | 600, 256, 575, 357 | 254 | D838D11595DD75D0… |
| 03 | 520, 258, 735, 356 | 253 | 019EB5EFD4913DC3… |
| 04 | 501, 261, 774, 350 | 253 | 99C24EF4C9D09AB6… |
| 05 | 447, 269, 880, 336 | 253 | 038A816BFB6090AE… |
| 06 | 359, 277, 1056, 316 | 253 | F146ED1B99D908D2… |
| 07 | 147, 277, 1486, 317 | 253 | B0A3B6F81FDD8815… |
| 08 | 104, 282, 1569, 325 | 253 | 12686BFA927120E6… |

- 9 帧均有真实 alpha 通道，最外圈像素全部透明；没有用黑色或棋盘格冒充透明背景。
- 纸面中心 alpha 为 253 或 254，原样保留。源 PNG 并非整片严格 255；运行时将近不透明纸面补到 255 的处理由主流程负责。
- alpha ≥ 128 且绿色通道明显高于红、蓝的可见像素计数，所有帧均为 0。
- 主体宽度按时间顺序为 `352 → 500 → 575 → 735 → 774 → 880 → 1056 → 1486 → 1569`，已消除回缩。
- 主体高度为 `381 → 357 → 357 → 356 → 350 → 336 → 316 → 317 → 325`。折面由收拢时的弯曲内面逐渐放平，纸层与边缘保留手绘变化。
- 各帧主体中心的横向范围为 3 像素、纵向范围为 10 像素。没有逐帧换画幅或另行归一化尺寸。
- 06 → 07 的展开幅度最大，宽度增加 430 个原始像素，呈现明显加速；需要在实际 14 FPS 播放中检查节奏。此项如实保留，没有通过程序补帧掩盖。

## 修正记录与真实生成顺序

重绘处理了：终帧最初过高；01 宽度超出下一帧，以及随后出现的高度问题；05 略超过 06 的宽度；07 过早平伏或高度跳变。候选稿并未全部采用，原始文件仍可追溯。

1. `08_initial` — 被后续重绘替换；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-ce66b077-2984-4dcb-b8fe-d9696bd494c3.png`
2. `08_geometry_correction` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-81fc6644-f395-4dcd-9b41-59fe9b70eeec.png`
3. `00` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-b36b7c65-1bf0-4642-a670-4b45c6c9c213.png`
4. `04` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-6d915804-af00-4647-87b1-f6a1f26c5edf.png`
5. `02` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-d2994b4b-014a-4412-8cc3-b8933ddd6b64.png`
6. `06` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-0a330cc5-c935-422c-9a09-665286f414b4.png`
7. `01` — 被后续重绘替换；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-1d89ddc2-0617-4041-b015-a0a697b6919a.png`
8. `03` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-b07cd8f6-9d6e-4e1e-8836-e9a18bf15ec1.png`
9. `01_width_correction` — 被后续重绘替换；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-5fb6d456-cb66-4aa3-9612-56cb71c00400.png`
10. `01_height_correction_rejected` — 被后续重绘替换；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-80de7945-d33d-46cc-bddb-d2e02963d1d3.png`
11. `05` — 被后续重绘替换；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-ea4e513e-607e-4362-b424-c6c3fd475c43.png`
12. `07` — 被后续重绘替换；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-2ee579e4-ca9d-4326-890a-80ce96f0c004.png`
13. `01_pose_correction` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-581f28cf-ac99-4865-89f9-900ff0d2b301.png`
14. `05_pose_correction` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-8f1090d8-d430-401a-8640-e7ded6ba00e2.png`
15. `07_pose_correction` — 被后续重绘替换；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-b7b79b07-f892-4750-b571-b7b32372f6b3.png`
16. `07_height_correction_rejected` — 被后续重绘替换；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-2c626d5e-c498-4350-85e4-2814fc52fab0.png`
17. `07_registered_pose_correction` — 保留；原图 `C:/Users/ZTCUS/.codex/generated_images/01a0ac74-51c9-7b21-9c13-cc238e760559/exec-561d9096-ec86-454e-b0d4-0dee8011f579.png`

## 验收边界

已完成逐张外观查看、alpha 检查、主体几何检查和归档。技术检查不等于玩家视觉验收，也不等于已通过实机流程。

主流程需重点检查 06 → 07 的展开速度、纸层落平，以及第 08 帧切换到独立静态模块纸时的外形、纸色和尺寸交接。本线不宣称这些运行时检查已经通过。


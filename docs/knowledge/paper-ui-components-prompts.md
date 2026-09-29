# 纸质 UI 小组件与纸角逐帧动画制作记录

日期：2026-09-17。执行方式：内置 `image_gen`。本条线只生成、检查和归档图片，没有修改生产代码、词条或工程规则。

## 来源与约束

- 风格参考均为已实际查看的官方截图：`work/references/book-of-travels/character.jpg`、`inventory.jpg`、`hud.jpg`。没有将项目旧的黑金 UI 用作参考。
- 已读取 ArtDirection.canvas 的 UI 文字与分组：沿用手工纸材质、安静层级和可读性，不复制官方文字、图标、人物或布局。
- 每次工具调用只生成一个组件或一个帧；没有生成联系表再切图。
- 所有选中原图复制至 `assets/art/ui/paper_v2/`；内置工具的原始输出另保留于生成目录。

## 实际派发顺序

1. `button`。
2. 同批独立生成 `button_hover`、`tab`、`portrait_frame`、`progress_track`；hover 引用本地 button。
3. 同批独立生成 `progress_fill`、`checkbox_off`、`slider_knob`、`close`。
4. `checkbox_on`，引用本地 checkbox_off。
5. 纸角帧依次 `00 → 08 → 04`。
6. 同批补 `02 / 06`；首批卷角幅度不合适，未选中。
7. 同批重做 `02 / 06`，保留相邻关键帧依赖并收紧角部范围。
8. 同批补 `01 / 03 / 05 / 07`；分别引用 `00+02`、`02+04`、`04+06`、`06+08`。
9. 追加独立 `arrow`；随后再做一次透明边缘清理并选用该版。

同批项目为独立并发调用，上列组内顺序是派发顺序，不代表完成顺序。帧依赖从未越过未完成的关键帧。

## 透明与画幅检查

使用 System.Drawing 对每张 PNG 的全部像素读取 alpha；审计脚本为 `work/paper_alpha_audit.ps1`，完整机器报告为 `docs/knowledge/paper-ui-components-alpha.json`。

| 文件 | 原始画幅 | 四角 alpha | 中心 alpha | alpha≥16 可见范围 x,y,w,h |
|---|---|---|---:|---|
| button.png | 2172×724 | 0/0/0/0 | 253 | 71, 132, 2032, 472 |
| button_hover.png | 2172×724 | 0/0/0/0 | 253 | 70, 129, 2035, 478 |
| tab.png | 1774×887 | 0/0/0/0 | 253 | 92, 221, 1612, 476 |
| portrait_frame.png | 1086×1448 | 0/0/0/0 | 0 | 71, 93, 945, 1270 |
| progress_track.png | 2172×724 | 0/0/0/0 | 0 | 35, 276, 2094, 216 |
| progress_fill.png | 2172×724 | 0/0/0/0 | 254 | 60, 267, 2058, 195 |
| checkbox_off.png | 1254×1254 | 0/0/0/0 | 252 | 377, 403, 513, 485 |
| slider_knob.png | 1254×1254 | 0/0/0/0 | 252 | 264, 266, 727, 722 |
| close.png | 1254×1254 | 0/0/0/0 | 253 | 225, 233, 810, 781 |
| checkbox_on.png | 1254×1254 | 0/0/0/0 | 253 | 376, 403, 515, 486 |
| turn_00.png | 1254×1254 | 0/0/0/0 | 253 | 266, 282, 728, 703 |
| turn_08.png | 1254×1254 | 0/0/0/0 | 253 | 265, 282, 731, 703 |
| turn_04.png | 1254×1254 | 0/0/0/0 | 253 | 265, 282, 730, 703 |
| turn_02.png | 1254×1254 | 0/0/0/0 | 253 | 266, 282, 730, 703 |
| turn_06.png | 1254×1254 | 0/0/0/0 | 253 | 264, 281, 733, 706 |
| turn_01.png | 1254×1254 | 0/0/0/0 | 253 | 265, 282, 731, 703 |
| turn_03.png | 1254×1254 | 0/0/0/0 | 253 | 264, 282, 733, 704 |
| turn_05.png | 1254×1254 | 0/0/0/0 | 253 | 264, 280, 733, 708 |
| turn_07.png | 1254×1254 | 0/0/0/0 | 253 | 264, 282, 733, 703 |
| arrow.png | 1536×1024 | 0/0/0/0 | 0 | 132, 102, 1306, 770 |

- 所有选中图片均为 `Format32bppArgb`，存在 alpha=0 的透明像素；没有将白底或棋盘格当成透明。
- `portrait_frame` 的中心为透明头像孔；`progress_track` 的中央留空。箭头在 V 内空隙和外部抽样 alpha=0。
- 生成展示可能显示 alpha=0 像素中保留的 RGB，或出现预览差异；工程合成以 PNG 的 alpha 为准。没有因预览误差破坏原始透明信息。
- 9 个纸角原图均为 1254×1254。提示词请求了小尺寸，但内置工具实际输出了较高分辨率原图；建议运行时统一缩到 256–512 画幅，保留同一锚点，不逐帧各自裁边。
- 帧间 alpha≥16 外轮廓的坐标差约 2–5 个原始像素；仍有独立绘制的轻微纤维变化。这项技术检查不等于动画在游戏里的最终视觉验收。

## 使用说明

- 文件名 `turn_00.png` 至 `turn_08.png` 为播放次序；推荐 `00,01,02,03,04,05,06,07,08,07,06,05,04,03,02,01` 往返播放。
- 提供同画幅缩到 512×512 的往返 APNG 预览：`work/paper-corner-preview.apng`。它是原有独立帧的顺序装配，未生成或切割联系表，不替代游戏内实际动画检查。
- 静态小组件可依据可见范围裁取纹理区域后缩放；button / hover、checkbox off / on 须共享同一范围，避免状态切换跳动。
- 本文记录素材交付与透明检查；原生 Godot 中的文字叠加、九宫格边距、实际控件尺寸和动画节奏由主代理继续整合验证。

## 逐图提示词与原始文件

### 01 · button.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/button.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-8343d431-af34-4a8d-a34b-d70b94f6af1d.png`
- 输入参考：`work/references/book-of-travels/character.jpg`、`work/references/book-of-travels/inventory.jpg`、`work/references/book-of-travels/hud.jpg`

```text
用途：手绘奇幻游戏的单独按钮贴图，不是界面截图。输入图片1和2只参考浅纸材质、灰米色、纤维笔触与自然纸边；图片3只参考低饱和手绘气质。不要复制参考的文字、图标或布局。只生成一个横向长条空白纸签按钮，单个物体，正面平视接近正交，宽高约3:1，完整置于画幅中央，四周少量透明留边。浅象牙/灰米色精致手工草纸，细纸纤维，自然细毛边，一到两层很薄的叠纸侧边，仅有极轻的灰赭色接触影；纸面中央保留干净平坦大面积空白供游戏程序叠加文字。边缘一两道极细手绘墨线，克制精致安静。透明背景，实际PNG alpha，按钮纸张之外所有像素透明，不能白底、棋盘格背景或摄影地面。无文字、无字符、无符号、无人物、无风景、无卡牌、无合集、无多组件、无重黑金框、无金属、无大卷轴、无复杂装饰。输出一张宽幅3:1透明PNG，button normal state。
```

### 02 · button_hover.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/button_hover.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-d731ef54-1162-4b42-84c1-846235e9d360.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/button.png`

```text
用途：为输入图1这一个已定稿纸签按钮生成悬停状态。输入图1是唯一编辑目标，保持同画布3:1、同大小、同位置、同形状、同边缘和空白中央；只能轻微抬起右下纸角，露出很窄的背面，并在按钮内缘增加一层非常淡的草绿色水彩刷痕作为悬停反馈。不要重画成另一张纸，不要加字、图标或其他物体。维持浅象牙细纤维草纸、灰赭细线与薄叠纸侧边。透明背景，保留实际PNG alpha，纸张外完全透明。悬停变化克制，动幅很小，一张仅一个组件。
```

### 03 · tab.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/tab.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-059e303e-d6bd-4755-b225-50f6119d4ae5.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/character.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/inventory.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/hud.jpg`

```text
用途：游戏浮窗上沿用的一个空白小纸页签，独立PNG。只参考所给官方截图中浅纸材质、自然毛边、细纸纤维和低饱和手绘墨线，不复制它们的文字、图标、场景或布局。浅象牙与灰米色手工草纸，少量灰绿/蓝灰/赭棕，精致干净、安静的手工异世界气质。组件之外必须为真正透明背景，实际PNG alpha，没有白底、棋盘格、场景或人物。每张图仅一个单独UI组件，不是mockup，不是合集，不含文字、数字、角色、卡牌插画、黑金边框或金属装饰。横向小矩形纸签，宽高约2:1，端部略有手工不规则，只有一层极薄背纸在右下露边，左上角一道轻微灰绿手绘笔触。正面正交视角，中央完全空白，可放短标题。物体完整位于画幅中央，四边少量透明留白，不能出现整本书或整张面板。
```

### 04 · portrait_frame.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/portrait_frame.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-99ad492b-58ab-4c7e-a3d4-d5aca874ec58.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/character.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/inventory.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/hud.jpg`

```text
用途：游戏人物关系页的一个竖椭圆纸质头像相框，独立PNG。只参考所给官方截图中浅纸材质、自然毛边、细纸纤维和低饱和手绘墨线，不复制它们的文字、图标、场景或布局。浅象牙与灰米色手工草纸，少量灰绿/蓝灰/赭棕，精致干净、安静的手工异世界气质。组件之外必须为真正透明背景，实际PNG alpha，没有白底、棋盘格、场景或人物。每张图仅一个单独UI组件，不是mockup，不是合集，不含文字、数字、角色、卡牌插画、黑金边框或金属装饰。只画一个竖椭圆环形相框，外轮廓比例约3:4，边环是浅象牙草纸，约为总宽度的百分之八，纤维细腻，毛边很轻，侧面薄薄两层纸。内外各一道极细不完全笔直的蓝灰墨线，左下角仅一笔小灰绿点染。整个椭圆中心必须挖空透明，可直接叠头像，绝对不能填纸、头像、颜色或白底。椭圆内洞和外部均真实alpha透明，只有环形纸相框不透明。正面，不倾斜，完整居中，无人物。
```

### 05 · progress_track.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/progress_track.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-77c51138-2265-4bc5-8b7d-9411ba1f9e73.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/character.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/inventory.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/hud.jpg`

```text
用途：游戏进度条的独立底槽贴图，适合横向拉伸/ninepatch。只参考所给官方截图中浅纸材质、自然毛边、细纸纤维和低饱和手绘墨线，不复制它们的文字、图标、场景或布局。浅象牙与灰米色手工草纸，少量灰绿/蓝灰/赭棕，精致干净、安静的手工异世界气质。组件之外必须为真正透明背景，实际PNG alpha，没有白底、棋盘格、场景或人物。每张图仅一个单独UI组件，不是mockup，不是合集，不含文字、数字、角色、卡牌插画、黑金边框或金属装饰。一条横向宽高3:1画幅内的扁长手绘空槽，居中，槽本体很窄、约占画幅高度的三分之一。上下边是浅象牙细纸条，边缘只有一条细蓝灰不均匀墨线。中轴通道必须从左到右连续完全挖空为透明，不得填充绿色、不画进度、不画分段刻度；两侧端头都开口，方便横向延展。纸槽外也完全透明。形状简约，手工纤维与极薄叠纸边，留出小透明边界，不加文字图标。
```

### 06 · progress_fill.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/progress_fill.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-42eb9635-2d07-462d-a69c-64f884fc2d63.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/character.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/inventory.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/hud.jpg`

```text
用途：游戏进度条的单独填充纹理。只参考所给官方截图中纸材质、自然毛边、细纸纤维和低饱和手绘笔触，不复制官方文字、图标、场景或布局。浅象牙与灰米色手工草纸，少量灰绿/蓝灰/赭棕，精致干净、安静的手工异世界气质。组件之外必须真正透明背景，实际PNG alpha，不要白底、棋盘格或摄影背景。每图只生成一个单独组件，禁止合集、mockup、多物体，无文字数字、无人物、无卡牌、无黑金框。只画一条连续横向灰绿色水彩墨迹笔触，浅鼠尾草绿与灰青绿，长宽比例约8:1，整体放在3:1宽画幅的中央，横向从左到右颜色均匀，中央没有空洞，颜料边缘细微自然渗化，末端克制略有刷毛痕，非荧光。没有纸槽、没有相框、没有刻度，不要画第二条；只这一条灰绿颜料形状，周围完全透明。可供游戏程序裁剪长度作为进度。
```

### 07 · checkbox_off.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/checkbox_off.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-d89a8538-77f2-44f7-aa64-3393e7fe2d71.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/character.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/inventory.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/hud.jpg`

```text
用途：游戏设置中未勾选复选框的独立贴图。只参考所给官方截图中纸材质、自然毛边、细纸纤维和低饱和手绘笔触，不复制官方文字、图标、场景或布局。浅象牙与灰米色手工草纸，少量灰绿/蓝灰/赭棕，精致干净、安静的手工异世界气质。组件之外必须真正透明背景，实际PNG alpha，不要白底、棋盘格或摄影背景。每图只生成一个单独组件，禁止合集、mockup、多物体，无文字数字、无人物、无卡牌、无黑金框。画一个小小的近正方形浅象牙纸方片，正面正交，宽高1:1。外缘轻微自然毛边，仅右下露出一层极薄灰米色背纸，纸片中心用蓝灰墨线手绘一个空心方格。格内完全空白，不带勾，不含任何符号。纸片宽约占正方形画幅百分之七十，四边保持透明留白。清晰简洁，缩到24像素时空方格仍易识别。
```

### 08 · slider_knob.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/slider_knob.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-50674032-d9e9-47fe-bbcb-134f490d7c02.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/character.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/inventory.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/hud.jpg`

```text
用途：音量滑条的一个小叠纸菱形滑钮，独立PNG。只参考所给官方截图中纸材质、自然毛边、细纸纤维和低饱和手绘笔触，不复制官方文字、图标、场景或布局。浅象牙与灰米色手工草纸，少量灰绿/蓝灰/赭棕，精致干净、安静的手工异世界气质。组件之外必须真正透明背景，实际PNG alpha，不要白底、棋盘格或摄影背景。每图只生成一个单独组件，禁止合集、mockup、多物体，无文字数字、无人物、无卡牌、无黑金框。只画一个正方形纸片旋转45度形成的菱形钮，正面正交，居中，单一小物体。浅象牙草纸两层薄叠纸，纤维细、轻微毛边，边缘一圈極细蓝灰墨线，底层偏灰米色只露少量边，中心一点极淡草绿水彩留白，不能像金属珠宝、宝石或立体水晶。正方形画幅，透明边距约百分之十五，无滑杆、无背景、无字。
```

### 09 · close.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/close.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-1ce6e133-f5d4-4267-855e-53b5d6821755.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/character.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/inventory.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/hud.jpg`

```text
用途：游戏窗口关闭按钮，单独一个透明图标。只参考所给官方截图中纸材质、自然毛边、细纸纤维和低饱和手绘笔触，不复制官方文字、图标、场景或布局。浅象牙与灰米色手工草纸，少量灰绿/蓝灰/赭棕，精致干净、安静的手工异世界气质。组件之外必须真正透明背景，实际PNG alpha，不要白底、棋盘格或摄影背景。每图只生成一个单独组件，禁止合集、mockup、多物体，无文字数字、无人物、无卡牌、无黑金框。只画一个小方形淡灰米色纸片，其上只有一个蓝灰偏赭色的手绘墨笔 X，两个短笔画交叉，线条略有干笔质感，粗细足够在24像素时清晰。X居中，纸片自然毛边且很薄，画幅1:1，纸片占画幅约百分之七十，外围真实透明。只这一个按钮，不要问号、文字、其他符号，不要圆形框、金属、复杂花纹。
```

### 10 · checkbox_on.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/checkbox_on.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-fe4d66b7-890c-40cc-9d9c-fc4a0cd7c838.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/checkbox_off.png`

```text
用途：将输入图的未勾选纸质复选框改为已勾选状态。输入图是唯一编辑目标。严格保持画幅、纸张大小、位置、轮廓、颜色、纤维、背纸和原来的蓝灰空心方格完全一致；仅在空方格内加一枚清晰的灰蓝墨笔勾（check mark），两笔，手绘干笔质感，适合缩小后辨识。不要增加新的框或其他物体，不要改变纸的形状或缩放，不要出现字、数字、摄影场景或合集。透明背景，保留真实PNG alpha，纸片之外全透明，单张图仅一个已勾选小组件。
```

### 11 · turn_00.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_00.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-ead80e09-456a-4709-98be-5c84903ca9d2.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/character.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/inventory.jpg`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/references/book-of-travels/hud.jpg`

```text
用途：对话继续提示的小纸角翻起动画，第00帧（完全平伏）。一张图只画这一帧，仅一个小纸角，绝不能联系表、序列图、多阶段或多个物体。输入官方截图只提供浅象牙手工纸的细纤维、自然毛边与灰米/灰绿水彩气质，不复制任何图标、文字、布局或人物。设计一个独立的近方形纸角片：右边与下边相交成右下角，左侧与上侧是细微撕纸边；它只是小纸片，绝不能画完整窗口、整页书或整本书。正面正交视角，纸角片本体约占正方形画幅中央的55%，画幅四周均匀透明留白，纸片不能接触画幅边缘。右下角此刻完全平伏，没有翻折，也没有折痕。纸张浅象牙/灰米色，边缘有极薄一层灰赭背纸，细柔纤维，只有纸本身，没有墨字、图形和装饰。光从左上，影子极浅且紧贴纸边。请输出512×512同画幅透明PNG，实际alpha透明，透明背景，不要白底或棋盘格。后续动画将仅轻轻翻起右下角，其余轮廓、尺寸、位置、纸纤维保持完全不动；本帧请建立一个非常简单稳定的小纸片作为基准。
```

### 12 · turn_08.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_08.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-a0bbe031-c9a6-446e-8f0c-27ea80b9128a.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_00.png`

```text
精确局部编辑：输入图是这段纸角轻翻动画的第00帧，生成第08帧（轻翻最大角度）。保持原图同画幅、纸片绝对位置和大小、左边、上边、纸纤维、光照和背景全部完全相同。唯一允许变化是纸片右下角约15%宽×15%高的小三角区域：把这个小纸角朝画面左上方轻轻卷起，露出浅灰米色背面与窄窄的柔和折下阴影，动幅很小，不做整页翻转，不改变其余85%以上的纸面。纸片主体严禁旋转、移动、缩放或换形，整个物体仍平伏。透明背景，真实PNG alpha，保留原有透明留边和像素画幅。无文字、无墨线图标、无额外物体。一张只有一个动画帧，绝对禁止多帧、联系表、左右对比图。风格继续是浅象牙细纤维草纸与细毛边。
```

### 13 · turn_04.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_04.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-a40a1d03-3deb-4386-9f9b-b3424dfc866b.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_00.png`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_08.png`

```text
动画精确补间，只输出一个第04帧。输入图1是第00帧平伏状态，输入图2是第08帧最大轻翻状态；需要它们正中间的50%状态。必须沿用这同一块浅象牙纤维纸角、同一画幅、绝对坐标、轮廓和光照。只改变右下角同一小区域：纸角卷起程度恰好在图1与图2之间，露出的浅灰背面约为第08帧一半，小小折下影也只有一半强度。左、上和纸张中央的纤维、色块、薄背纸层全部锁定，不能移动、缩放、旋转纸片或重新设计纸张。低幅度、平顺、安静。背景完全真实alpha透明，保留原画布透明留白，绝无文字、符号、额外纸片、摄影地面。单图单帧，禁止联系表、分镜、拼图、左右比较。
```

### 16 · turn_02.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_02.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-bc35d74f-bbbd-4b30-8801-9b4adc48b794.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_00.png`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_04.png`

```text
精确局部编辑，第02帧修订。第一张平伏纸片是唯一基底，第二张只用于说明将来第04帧的动作上限，不能直接复刻第二张的卷角。请只让第一张纸片的右下尖端发生极小翘起：1254方形画布上，新出现的折角三角区域最长边约50像素（只占纸片宽度约7%），窄窄露出背面，比第二张卷角明显小，最多为其四分之一面积。不要挪动整张纸、不要改变纸边、纸纤维和光照。当前是刚刚离开平伏的25%时刻，绝不是已翻起状态。所有变化限于右下最末端的小角，中央95%以上完全保留第一张。保持同画幅和同坐标，透明背景真实alpha，不加任何文字、符号、道具、分帧框。一张图只生成一个帧，禁止联系表。
```

### 17 · turn_06.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_06.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-3b9117f4-9da8-49ca-bc91-67428ab75dd6.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_08.png`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_04.png`

```text
精确局部编辑，第06帧修订。第一张是第08最大轻翻，第二张是第04较小轻翻。以第一张为固定基底，仅将右下卷角幅度稍微减小：露出的背面三角面积减少约25%，卷曲边缘向原来的右下尖端收回少许，结果必须小于第一张、略大于第二张。绝对不允许卷角比第一张更大。纸张整体、画幅、位置、大小、外围毛边、左边上边、纸纤维与光照全部保留不变，不旋转不缩放。动画动作只是细小的角部变化，不是翻整页。透明背景，真实PNG alpha，同样透明边距，无字无图标无新物体。只输出这一个第06帧，严禁联系表、拼图或多个姿势。
```

### 18 · turn_01.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_01.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-62db9447-1f0a-477d-8364-ad7ab049b0ea.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_00.png`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_02.png`

```text
单帧动画局部补间。只输出第01帧这一张PNG。参考图1是第00帧，参考图2是第02帧；目标在这两个直接相邻关键帧之间的时间正中间。纸角仅有一点点离纸，几乎平伏，绝不能出现已经明显卷起的大三角。严格固定原始画幅、纸片的绝对位置、宽高、外轮廓、左上缘、中央纸纤维、浅象牙/灰米色和光照。允许变化的区域仅是右下同一个小纸角及其细窄投影，像同一张纸被微风轻抬。不要旋转或移动整片，不要重新设计材质，不要新增折角。透明背景、实际alpha，无白底无棋盘格，无人物无场景无字无图标。一个物体一个帧，绝对禁止多帧联系表、拼贴、并排对比。
```

### 19 · turn_03.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_03.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-55b80135-4ae1-4970-a032-f312ee3aef47.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_02.png`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_04.png`

```text
单帧动画局部补间。只输出第03帧这一张PNG。参考图1是第02帧，参考图2是第04帧；目标在这两个直接相邻关键帧之间的时间正中间。小折角应比第一张稍大、但明确小于第二张，露背面积取两者中间。严格固定原始画幅、纸片的绝对位置、宽高、外轮廓、左上缘、中央纸纤维、浅象牙/灰米色和光照。允许变化的区域仅是右下同一个小纸角及其细窄投影，像同一张纸被微风轻抬。不要旋转或移动整片，不要重新设计材质，不要新增折角。透明背景、实际alpha，无白底无棋盘格，无人物无场景无字无图标。一个物体一个帧，绝对禁止多帧联系表、拼贴、并排对比。
```

### 20 · turn_05.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_05.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-4ddea7ed-dabf-48ed-8f38-de8423d418be.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_04.png`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_06.png`

```text
单帧动画局部补间。只输出第05帧这一张PNG。参考图1是第04帧，参考图2是第06帧；目标在这两个直接相邻关键帧之间的时间正中间。两张参考的变化很小，所以目标也只应是极小中间变化，不能放大动作或重新做大卷角。严格固定原始画幅、纸片的绝对位置、宽高、外轮廓、左上缘、中央纸纤维、浅象牙/灰米色和光照。允许变化的区域仅是右下同一个小纸角及其细窄投影，像同一张纸被微风轻抬。不要旋转或移动整片，不要重新设计材质，不要新增折角。透明背景、实际alpha，无白底无棋盘格，无人物无场景无字无图标。一个物体一个帧，绝对禁止多帧联系表、拼贴、并排对比。
```

### 21 · turn_07.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_07.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-2addb253-025a-4c5a-b1b6-18c43587be35.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_06.png`、`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/turn_08.png`

```text
单帧动画局部补间。只输出第07帧这一张PNG。参考图1是第06帧，参考图2是第08帧；目标在这两个直接相邻关键帧之间的时间正中间。比第一张稍微更卷起，但必须小于第二张的最大状态，不能超过第二张。严格固定原始画幅、纸片的绝对位置、宽高、外轮廓、左上缘、中央纸纤维、浅象牙/灰米色和光照。允许变化的区域仅是右下同一个小纸角及其细窄投影，像同一张纸被微风轻抬。不要旋转或移动整片，不要重新设计材质，不要新增折角。透明背景、实际alpha，无白底无棋盘格，无人物无场景无字无图标。一个物体一个帧，绝对禁止多帧联系表、拼贴、并排对比。
```

### 23 · arrow.png

- 最终路径：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/assets/art/ui/paper_v2/arrow.png`
- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-c1df8845-7189-4096-8a68-f45b54e25bff.png`
- 输入参考：`C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/work/paper-arrow-candidate.png`

```text
精准背景清理：保留输入图中现有单个蓝灰墨笔 V 形箭头的形状、两个笔画的位置、粗细、颜色和干笔纹理。删除它周围所有模糊光晕、柔光、投影、烟雾与背景色。输出仅有硬而自然毛边的墨笔笔画，笔画之外的区域必须100%透明(alpha=0)，包括V形中间的空隙；完全禁止任何外发光、环境光、渐变阴影或纸底。不要重新设计箭头，不加框，不加其他图案和文字。真正透明PNG，单个图标，独立一张。
```

## 未选候选与修订

### 候选 1 · turn_02.png

- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-44a9bc56-3179-47c9-a743-03f9f96c6985.png`
- 处理：卷角幅度偏离相邻关键帧范围，改用后续针对性修订。

```text
动画精确补间：第一张是前关键帧 turn_00.png，第二张是后关键帧 turn_04.png。仅输出它们时间正中间的一个 turn_02.png，25%轻翻，刚刚离开平伏，卷起程度只有第04帧一半。只轻微改变同一个右下纸角小区域，卷曲边缘与窄影平顺插值；纸主体、左边、上边、绝对大小和位置、相机、像素画幅、浅象牙色、细纸纤维及背纸层全部保持输入图不动，不能重构、位移、旋转或缩放。仍是同一片安静精致的手工草纸，非整页翻书。背景必须真实alpha透明，四边透明留白与原图一致。没有文字、符号、场景、额外物体；一张图仅一个动画帧，禁止联系表、并排图、拼贴或多个动作。
```

### 候选 2 · turn_06.png

- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-b6ad898b-c9da-4504-b418-8cdef35f93f7.png`
- 处理：卷角幅度偏离相邻关键帧范围，改用后续针对性修订。

```text
动画精确补间：第一张是前关键帧 turn_04.png，第二张是后关键帧 turn_08.png。仅输出它们时间正中间的一个 turn_06.png，75%轻翻，折角介于第04与第08帧之间，不要已经达到第08帧幅度。只轻微改变同一个右下纸角小区域，卷曲边缘与窄影平顺插值；纸主体、左边、上边、绝对大小和位置、相机、像素画幅、浅象牙色、细纸纤维及背纸层全部保持输入图不动，不能重构、位移、旋转或缩放。仍是同一片安静精致的手工草纸，非整页翻书。背景必须真实alpha透明，四边透明留白与原图一致。没有文字、符号、场景、额外物体；一张图仅一个动画帧，禁止联系表、并排图、拼贴或多个动作。
```

### 候选 3 · arrow.png

- 原始文件：`C:\Users\ZTCUS\.codex\generated_images\01a0ac74-51c9-7b21-9c13-cc238e760559\exec-7e68f884-6318-476c-82d2-d7c408ce1f41.png`
- 处理：预览疑似带光晕，追加透明边缘清理；最终选中版已抽样确认图标之外 alpha=0。

```text
用途：纸质游戏设置下拉框的一个独立 V 形向下箭头图标。参考图只用于同样的蓝灰/微赭墨笔颜色和细微干笔质感；不要保留它的 X，不要保留大纸片。只画一枚清晰向下的墨笔 V，两条较短有手工笔触的斜线相交成向下尖端，线宽足够缩到16至24像素辨识，横向宽度略大于高度。造型克制，不是装饰花纹、文字或飞鸟，不加横线，不闭合成实心三角。正面、居中，一张图仅这一个箭头，四周透明留白。真实PNG alpha透明背景，纸外无任何颜色，绝不白底、棋盘格、场景、阴影背景或UI合集。
```

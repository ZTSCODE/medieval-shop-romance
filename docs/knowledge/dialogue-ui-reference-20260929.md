# 对话框参考图接入

当前版本为 dialogue-panel-v3.png：用户否决第二版颜色漂移与锐化般纹理，要求执行修正。第三版回到原截图裁片，仅要求保持颜色、明暗、柔和笔触和外形，去文字、透明背景、不带投影，不再加入精细干笔或锐利轮廓等额外风格描述。当前尺寸和代码后投影继续保留，尚待用户视觉验收。

后续修正：用户否决第一版偏糊、尺寸过大，要求完整重生并用代码加后方阴影。当前素材改为 dialogue-panel-v2.png（2172×724），清除图内姓名牌投影，宽度按参考568/1672屏宽计算，小屏保留可读下限；阴影由 reference_dialogue_paper.gd 使用原图透明轮廓的九次轻量偏移绘制，参数可独立调整。长文本固定框宽并滚动，12项实机检查通过，当前日志 runtime-v2.log。

用户于 2026-09-29 要求按所给截图裁取、去背景并重绘对话框，随后授权接入并提供游戏内截图。正式对话框使用 assets/art/ui/dialogue_20260929/dialogue-panel.png，通过 reference_dialogue_paper.gd 整图等比显示，姓名牌与左下植物已在图内；对白、姓名与继续按钮由原有控件绘制。该方向仅影响对话框，不改变其他窗口皮肤。

当前正式内容集合为空。tests/dialogue_asset_runtime_capture.gd 在隔离存档的真实 TableApp 中注入预览 DialogueFlow，文本集中在 tests/fixtures/dialogue_asset_preview.csv；截图输出 outputs/dialogue-ui-20260929，不能把预览文本当正式剧情。修改前备份位于该输出目录的 before。Godot 4.7.1 OpenGL 实机完成 1600×900 与 960×640 截图，10 项检查全部通过，含继续推进、暂停阻止推进、结束收起与小屏长文布局；日志为同目录 runtime.log。

# 真棋盘木纹与边框投影（2026-10-01）

用户启用了原先隐藏的真棋盘（`table_environment_editable.tscn` 中的 `BoardThickness` 与 `WoodRim0–3`），并要求把背景假棋盘（`BoardSurface` 第 1 面）的木纹移到真棋盘上，同时解决四边边框的纹理拉伸。现在 `BoardThickness` 与假棋盘使用相同参数：`board-wood-retained.png`、6 米一铺、亮度 0.58。拉伸的原因是：场景根节点绕 X 轴旋转了 90°，而边框按世界 xz 坐标取纹理，旋转后其中一个轴在面上恒定，纹理就被拉成条纹。共享着色器 `painterly_tiling.gdshader` 新增了 `box_projection`（盒体逐面投影：顶/底面取 xz，侧面取长度×高度）和 `grain_along_z`（把木纹转到 z 向长度方向）两个选项，默认均关闭，不影响草地等其他材质。上下边框使用 `ShaderMaterial_m40u5`，左右边框使用新的 `ShaderMaterial_rimz`（开启 `grain_along_z`）。假棋盘的纹理保留未动，被真棋盘遮住。

截图注意：游戏开启 HDR 后，`get_texture().get_image()` 回读的是线性数值（RGBAH），直接存 PNG 会异常偏黑，需要先逐像素用 `linear_to_srgb()` 转换，示例见 `tests/board_wood_capture.gd`。验证方法：运行 `tests/editable_environment_suite.gd` 与 `tests/board_wood_capture.gd -- --flow-qa [--after]`，截图输出到 `outputs/board-wood/`。场景文件由人工维护，是唯一来源；原场景生成脚本和 `table_stage_3d` 中从未调用的旧棋盘/远景搭建代码已于 2026-10-01 经用户同意删除。

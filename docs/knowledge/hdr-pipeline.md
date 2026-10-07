# HDR 输出链路（2026-10-01）

主视口、TableStage3D 的 CardCanvas 和 TableViewport3D 启用 HDR 2D，保留浮点高光。选中及落点预览共用 card_inset_gold shader，HDR 高光按窗口实际 output_max_linear_value 计算并封顶 2 倍余量；SDR 余量为 1。不会整体提高 UI 亮度。灯火插画尚未增加独立发光遮罩，完整场景的 HDR 美术校准未完成。

tests/hdr_pipeline_capture.gd 在隔离配置中比较同场景、同镜头的 HDR/SDR，保存 EXR 原数据、统一亮度压缩 PNG 与输出状态报告。baseline 参数恢复三个视口的旧格式用于复测，不代表完整旧源码。outputs/hdr-pipeline-20261001/backup 保存修改前配置和棋盘脚本；游戏设置开关原有 19 项检查通过。普通 PNG 不能重现屏幕的物理 HDR 亮度。

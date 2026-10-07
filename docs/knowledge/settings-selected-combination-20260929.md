# 设置界面选定组合

用户选图1（`exec-4577dbaa-fda7-43ed-bf7f-a99bf6a50ed9.png`）的主书页轮廓、材质、顶部图标书签和颗粒细滑条；按钮及下拉使用图2（`variant-c.png`）的浅灰褐纸条；开关采用图3（`variant-b-dark.png`）“开 / 关”文字与当前状态短下划线，不使用分段按钮背景。独立纸页、纸条资源位于 `assets/art/ui/settings_20260929/selected-*`，未裁剪概念图拼接生产资源。主纸页生成实际1581×995，不能宣称4倍或4K。

HDR 已按 Godot 4.7 显示器输出 API 接入设置持久化和能力检查，2026-09-29 当时的项目 `gl_compatibility` 不支持，显示禁用开关及原因；不能用 `hdr_2d` 假冒 HDR 输出，不擅自切渲染器。旧配置缺失 HDR 项按关闭处理，测试与预览使用隔离配置，不覆盖用户存档。HDR 专项19项、存储回归97项通过；`runtime-selected-pointer.log` 的分类点击、下拉、开关指针操作、保存、本地化、返回和960×640布局检查全部通过，无脚本错误。该轮实机图位于 `outputs/settings-book-20260929/`；视觉最终验收仍由用户决定。2026-10-01 用户已批准迁移至 Forward+ / D3D12，现行配置及 HDR 链路见 [渲染器记录](renderer-forward-plus.md) 和 [HDR 记录](hdr-pipeline.md)；上述禁用状态与检查数量仅描述 9 月 29 日版本，不代表当前输出能力。

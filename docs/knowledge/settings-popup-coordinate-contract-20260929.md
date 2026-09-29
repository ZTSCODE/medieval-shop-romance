# 下拉弹窗坐标约定

PopupMenu.size 是窗口单位，StyleBox 绘制使用 get_visible_rect().size 的逻辑单位。settings_book_skin.gd 锁定展开动画完整纸面时必须使用后者；按钮的逻辑宽度必须乘弹窗最终 content_scale_factor 后再与原生窗口宽度比较。直接混用造成纸面过小，文字和高亮看似溢出，但实际是底板未覆盖真实菜单。

OptionButton.show_popup 会根据按钮祖先变换重新计算弹窗缩放，独立测试只设置 popup.content_scale_factor 无法覆盖实际游戏路径。settings_popup_scaled_suite.gd 使用真实按钮缩放，settings_popup_game_suite.gd 验证完整游戏的 3840、1672、960 宽窗口；原有 cursor_long_popup_suite.gd 继续负责滚动、选中及动画命中回归。

滚动条由 settings_popup_motion.gd 管理绘制透明度，保留原生滚动区域布局。展开期间不响应滚动值校正；完整展开后，有溢出内容且滚动值改变才显示，停止约 0.65 秒后以 0.18 秒淡出。关闭和重新展开均清理旧显隐动画。

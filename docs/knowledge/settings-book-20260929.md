# 设置分类书页

用户要求参考图的顶部分类书签和薄叠页结构，纹理沿用主菜单灰褐纸面。此前添加左侧单项按钮是错误理解，已移除；显示、音频、语言各分类内直接展现全部控件，不设置第二层导航。设置值继续通过原 GameSettings 写入，全部选项保留，从主菜单返回主菜单，从 Esc 返回暂停页。复用已有本地化键。

用户进一步明确要原图的外轮廓与书页形状，而非靠左侧装订线表现；同时否决各控件混用样式。当前改用 book-silhouette-v5.png 的空白参考轮廓（保留纸肩、错叠薄页，移除装订线），运行时转灰褐色；settings_book_skin.gd 统一下拉、弹出菜单、返回、滑条、勾选的材质和墨色，复用主菜单纸纹。设置分页和书签遮挡逻辑仍在 settings_panel.gd、settings_book_paper.gd。tests/settings_book_runtime_capture.gd 验证鼠标切换、全部控件可见、持久化、英文、返回与横纵溢出，输出 outputs/settings-book-20260929；支持 --flow-qa --preview-hold。视觉效果仍待用户确认。

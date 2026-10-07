# HDR 下手绘配色校准（2026-10-02）

主菜单和通用菜单的旧重着色公式先计算 sRGB 纸张亮度，再用选中色除以原纸基准；开启 HDR 2D 后纹理采样变成线性颜色，必须先还原至 sRGB 完成手绘配色，再转回线性输出。两类按钮及卡牌金边共用 painted_canvas_color.gdshaderinc，并由所在视口 use_hdr_2d 设置 linear_canvas。金边仅在线性输出之后增加 HDR 高光，避免把香槟色直接误当线性颜色而发白。主菜单与通用按钮纹理分别标定基准亮度 0.218 / 0.219，共用原 SELECTED_PIGMENT。

审计其余 shader：card_art_edge、solar_marker、paper_unfold、button_press 只操作透明度或几何；3D 地面及活动草材质有 source_color 输入，本来在线性空间运算；paper_mask_layer 的 brush 为强度数据，不能误加 source_color。旧 2D table_vegetation 与旧纸肤不属当前显示路径。当前对白、配方、关系纸底走原贴图绘制，未发现相同重着色公式。备份、主菜单与暂停前后图、空记录页及 HDR 开关截图在 outputs/ui-linear-color-20261002；普通按钮区域开关 HDR 后截图差值为零，金边高光采样仍可超过 1，完整 HDR 场景美术校准仍非本次完成范围。

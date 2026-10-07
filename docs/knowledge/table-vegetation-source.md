# 棋盘外沿交互植被

版本范围（2026-10-07）：下文保存早期 2D 草甸、素材来源、接口与测试历史。现行植物来自人工维护的 `scenes/world/table_environment_editable.tscn`，编辑入口见 [植物制作手册](../art/manual-plant-production.md) 和 [Grass Painter](../tools/grass_painter.md)；不能按下方旧 CanvasLayer 或程序生成接口重建当前场景。

## 最新修正：世界坐标草甸

用户否决上一轮草形和屏幕边框铺法，明确参考`game/scenes/world/tile_templates/wilderness_meadow_0002.tscn`。只读解析结果表明，鲜绿`GrassField`为0株，实际为`GrassField4`细草15591株、`GrassField2`深灌丛7968株、`GrassField3`白花3674株，另有38株静态树。本版按约57.3%/29.3%/13.4%复用前三层，保留各层源区域色强度、饱和度与自然色参数；没有搬入3D灯光，因此不将当前渲染等同于原场景最终光照。

`TableVegetation`现为`board.world`子节点，`configure_world(TableState.WORLD_BOUNDS)`替代屏幕布局。2200株固定根点位于3200×2200棋盘之外380世界像素的环内，全部直立，不沿四边旋转；3种共享材质按512×256空间块批绘。鼠标位置与速度通过world逆变换送入，8条衰减事件控制拨动和点击回弹，暂停冻结elapsed。缩放、平移、窗口变化不会重新随机或改变根点。牌桌保留原逻辑尺寸及存档边界；默认镜头位于牌桌中央，缩小视野或平移到边界才能看到外侧草地。

原生`tests/meadow_world_suite.gd`14项通过，检查世界父节点、实际素材、所有根点外置、镜头平移、窗口变化不重排、鼠标坐标转换、暂停、GPU内外覆盖、探索及存档。截图与只读源参数归档在`outputs/meadow-world-review/`。旧`vegetation_runtime_suite.gd`入口转向新世界测试。

## 以下为已弃用的屏幕边框方案记录

## 来源与授权范围

用户明确授权复用本机旧工程植被代码及素材。本次只读取旧工程；三个透明 PNG 原样复制到当前工程，不生成新美术，不改旧工程。

- `C:/Users/ZTCUS/Documents/game/addons/grass_painter/grass_material.gdshader`：第 69–87 行双频风波与包络；第 90–115 行径向方向与速度方向的 0.72 混合、smoothstep 范围；第 119–134 行根部 1.75 次幂与压缩；第 143–183 行自然色变化、区域权重与 painted_value。
- `C:/Users/ZTCUS/Documents/game/addons/grass_painter/grass_patch_3d.gd`：第 535 行固定随机种子，以及独立尺度、相位、颜色参数的实例设计。没有搬运 3D 节点、编辑器画笔、碰撞或存档。
- `assets/props/grass_clump_scene_reference_v2.png` → `assets/art/vegetation/grass_clump.png`。
- `outputs/component_library_v2/by_category/vegetation/legacy_validated/afk-book-web-v3/afk-book-web-v3__05-fine-shoreline-grass-cluster.png` → `assets/art/vegetation/fine_grass.png`。
- `outputs/component_library_v2/by_category/vegetation/legacy_validated/afk-book-web-v4/afk-book-web-v4__04-white-flower-shoreline-grass.png` → `assets/art/vegetation/white_flowers.png`。

## 本项目适配

实现位于 `scripts/view/table_vegetation.gd` 与 `assets/shaders/table_vegetation.gdshader`。改为 canvas_item，每株 9×13 顶点，根部保持固定，叶尖按根部权重弯曲。三种纹理只在初始化按 alpha 实际包围盒裁出运行纹理，各自网格保持图像比例；源文件完整保留。固定种子 80 株，细草 55%、草团 35%、白花 10%，沿四边分簇留空，尺寸变化不会重新随机。

风波沿用源公式，世界米尺度换为屏幕像素。鼠标替代玩家位置/速度；原工程只有即时压弯，本项目新增阻尼弹簧、速度衰减和点击短脉冲。回弹不是旧工程已有功能。无采集或资源效果，不接受或消耗输入事件。

颜色使用源 painted_region 权重方式，区域色改为低饱和蓝灰绿；完全重映射草叶而非直接乘色，避免原图亮绿荧光，白花保留浅色。

## 接口及集成

- `set_layout(viewport_size, board_rect, exclusion_rects)`：逻辑屏幕坐标，排除真实棋盘内部及最多 16 个 HUD/市场/剧情矩形。
- `set_pointer(point, velocity, impulse=false)`：逻辑屏幕位置与像素/秒速度；点击可传 true。
- `elapsed` 与 `patches` 公开供检查，后者含 node、material、variant、bend、spring_velocity。
- 节点置于独立屏幕 CanvasLayer，保持原点为零，不能跟随棋盘 Camera2D。根节点控制主菜单隐藏；默认 PAUSABLE，隐藏也不推进。自定义 elapsed 替代 shader TIME，Esc 与阅读暂停自然冻结。
- 可调整 patch_count、distribution_seed、wind_strength、wind_speed、interaction_strength、disturbance_radius、spring_frequency、spring_damping；数量与种子在初始化读取，风和交互强度运行时生效。

## 验证边界

已完成 headless 编辑器导入及 `work/vegetation/smoke.gd`：80 株、117 顶点、局部脉冲、暂停冻结、重复布局不随机、扰动衰减通过。随后 Godot 原生 `tests/vegetation_runtime_suite.gd` 共14项通过，验证GPU确实绘制植被、牌桌与HUD内部像素不受植被影响、鼠标拨动与点击回弹、Esc与阅读冻结、尺寸变化保留同一批实例、卡牌组合探索和对话存档正常。原生错误日志为空，截图与报告归档至outputs/vegetation-review；最终草带密度与外观仍待用户视觉接受。

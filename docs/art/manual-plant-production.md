# 单株植物资产制作与 Godot 场景美术流程

当前推荐工作流是：每棵重要近景植物使用一个 `ManualPlant3D` 节点手动摆放；大面积远景或填充草仍可保留 Grass Painter。单株模板会自动获得摄像机平行、自然风、鼠标拨动、暖光、根部固定和透明边缘处理。

## 一、制作植物 PNG

植物原图应满足：

- PNG，透明背景，使用 sRGB 颜色。
- 推荐 1024–2048 像素高；细小花草可以更低，但不要先做成很小的游戏显示尺寸。
- 植物根部放在画布底边中央，主体上方和左右保留少量透明空间，避免风吹时碰到图片边界。
- 透明区域必须真的带 Alpha，不能使用黑底、白底或棋盘格截图。
- 不烘焙地面阴影、环境光、鼠标光或发光；这些由游戏统一处理。
- 不添加文字、边框或背景地面。
- 笔触、颜色和明暗参考现有 `assets/art/forest_rebuild/editable/` 资源；轮廓需要清楚，避免半透明雾边。

建议存放到：

`res://assets/art/environment/plants/manual/`

## 二、Godot 导入设置

把 PNG 复制到工程后，在 FileSystem 中选中它，在 Import 面板检查：

- 压缩使用 VRAM Compressed，适合游戏中的 3D 贴片。
- `Mipmaps > Generate` 开启，防止远处植物闪烁。
- `Process > Fix Alpha Border` 开启，减少透明边缘黑线或白线。
- 不开启 Repeat；植物不是平铺纹理。
- 不开启 Premultiplied Alpha。
- 修改后点击 `Reimport`。

如果细叶在远处消失，可先把植物节点的 `Alpha Scissor` 从 0.18 降到 0.12–0.16；不要直接关闭 Alpha Scissor，否则重叠植物可能重新出现透明排序闪烁。

## 三、添加一棵可手动选择的植物

1. 打开 `res://scenes/world/table_environment_editable.tscn`。
2. 在 FileSystem 中找到 `res://scenes/world/manual_plant_3d.tscn`。
3. 把它拖到场景树的 `EnvironmentRoot/EditableVegetation/EditableManualPlants` 下。
4. 给实例改一个清楚的名字，例如 `Fern_Left_01`。
5. 在 Inspector 的 `Plant Art > Plant Texture` 中拖入新 PNG。
6. 调整 `Plant Height Meters`。宽度会按原图比例自动计算，不会拉伸。
7. 用移动工具摆放根点。`Snap To Folded Surface` 开启时，节点会自动贴合棋盘平面、倒角或后坡。
8. 按 `Ctrl+D` 复制后，修改 `Variation Seed`，可以让风相位与轻微色差错开。
9. 按 `Ctrl+S` 保存场景。

尽量通过 `Plant Height Meters` 改大小，不要随意把 Node3D 的 X/Y/Z 缩放改成不同数值，否则会产生非等比拉伸。需要整体缩放时保持三个轴一致。

### 实际摆放时常用的编辑器操作

- 场景树中选中植物节点后，按 `W` 切到移动，`E` 旋转，`R` 缩放，`F` 把编辑器视角聚焦到当前植物。
- 开启插件工具栏的 `Game View` 后，编辑器摄像机与游戏机位一致，适合判断最终构图；需要检查根点时关闭 `Game View`，用自由视角观察侧面。
- 场景根节点本身按项目坐标立起，不要再旋转 `TableScene`。植物模板会把你拖动的位置换算到棋盘平面、倒角和后坡。
- 一棵植物必须是 `EditableManualPlants` 的直接或间接子节点。不要把它拖到 `BoardSurface`、`CardPlane` 或 UI 节点下面。
- 画笔草层内部是 `MultiMesh`，一整层只会被当作一个渲染对象，无法逐棵选中。需要单独调整的草，改用本模板重新放置。

## 四、更换现有单株贴图

选中 `EditableManualPlants` 下的植物，在 Inspector 中：

- 将新 PNG 拖到 `Plant Texture`。
- 调整 `Plant Height Meters`，宽度自动跟随图片比例。
- `Flip Horizontal` 用于左右翻转，避免用负数缩放。
- `Color Multiplier` 调整它与夜景的融合亮度；默认 0.86，前景深色植物可以降到 0.65–0.80。
- `Alpha Scissor` 控制透明边缘裁切。

替换贴图不会丢失植物的位置、风参数或交互参数。

## 五、风与鼠标交互参数

单株植物默认与密集草使用相同设置：

- `Wind Enabled`：自然风总开关。
- `Wind Strength = 0.105`：旧版自然风幅度。
- `Wind Speed = 1.05`：风场移动速度。
- `Interaction Enabled`：鼠标拨动开关。
- `Interaction Strength = 0.30`：鼠标摆动幅度。
- `Interaction Radius = 1.30`：影响半径，单位为米。
- `Variation Seed`：不同植株的自然风相位。

石头、箱子等不会摆动的透明贴片可以复用模板，但应关闭 `Wind Enabled` 和 `Interaction Enabled`。

## 六、编辑棋盘和外围地面纹理

选中 `BoardSurface`，它有两个 Surface Override Material：

- Surface 0：棋盘外围林地，目前为 `forest-floor-tile.png`。
- Surface 1：棋盘褐色泥地，目前为 `earth-tile.png`。

展开对应材质的 Shader Parameters：

- `Grain`：替换平铺纹理。
- `Tile Size Meters`：控制每次重复覆盖的世界尺寸；数值越小，纹理越密。
- `Surface Tint`：整体乘色。白色表示保留原图颜色，深色会把笔触压暗到看不见。
- `Unfolded Coordinates`：必须保持开启，让棋盘、倒角和后坡连续采样。

地面纹理必须是不透明正方形 PNG，建议 1024–2048 像素，开启 Mipmaps 和 Repeat。不要直接把一张低分辨率整景图拉伸覆盖整个棋盘。

当前褐色棋盘使用 `res://assets/art/forest_rebuild/earth-tile.png`。替换时可以直接把新的纹理拖到 Surface 1 材质的 `Grain`，也可以覆盖同路径文件后执行 `Reimport`。`BoardThickness` 是旧的纯色支撑盒，当前保持隐藏；不要重新显示它，否则会遮住起伏棋盘上的笔触材质。

## 七、其他场景美术编辑

- `EditableLandmarks`：树、背包、地图、杯子、灯笼等独立道具，可直接移动、复制、隐藏或替换 `Texture`。
- `EditableDistantLandmarks`：远处树、城镇和镇旁道具。远景物体应减少尺寸和对比度，形成景深。
- `DistantSkyWorldPlane`：最远背景平面。替换贴图时同步修改 QuadMesh 宽高比，避免拉伸。
- `WarmKey`：暖色主方向光。
- `CoolFill`：冷色补光。
- `TableLightEnvironment`：环境底光。不要用它补偿单张过暗贴图，应先调整该贴图的 `Color Multiplier`。
- `WoodRim0–3`：棋盘四边木框；修改材质时四边应继续共用同一平铺纹理。
- `BoardSurface`：连续棋盘、倒角和后坡网格。移动植物和建筑即可，除非需要改变地形轮廓，否则不要直接改它的顶点。

### 替换其他透明美术组件

1. 在场景树选中对应的 `Sprite3D` 或手动植物节点。
2. 普通静态道具在 Inspector 替换 `Texture`；会摆动的植物替换 `Plant Texture`。
3. 保持 `Billboard` 或模板摄像机朝向逻辑，不要直接把贴片旋转到朝向某个固定视角。
4. 若图片比例变化，同步检查普通 `Sprite3D` 的 `Pixel Size`；手动植物会按贴图宽高比自动更新，不需要手算。
5. 回到 `Game View` 检查近景遮挡、远景缩小关系和透明边缘，再运行游戏确认风、鼠标拨动与暖光。

编辑时开启 `Game View`，完成局部摆放后关闭锁定，用自由视角检查根点是否悬空或穿入地面，最后再回到游戏机位确认构图。

## 八、哪些内容不要手动修改

- 不要编辑植物节点内部生成的 `PlantRenderer` 或 `__GrassRenderer`。
- 不要编辑 `grass_positions` 等数组；它们属于画笔图层数据。
- 不要把 UI、卡牌或字幕放进这个 3D 环境场景。
- 手动美术调整后不要运行 `tools/build_editable_table_scene.gd`，该脚本用于重建初始场景，可能覆盖人工摆放结果。

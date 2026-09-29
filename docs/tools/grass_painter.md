# 可编辑牌桌环境与植被画笔

牌桌、地形、灯光、近景道具和三层近景植被已经集中到：

`res://scenes/world/table_environment_editable.tscn`

游戏运行时直接实例化这张场景，保存后的修改会进入游戏。场景根节点已经绕 X 轴旋转 90°，在编辑器里以竖直布景显示；游戏相机和动态卡牌平面挂在同一根节点下，运行时取景保持不变。

近景和远景植物都保存在可刷的 MultiMesh 图层中，远处城镇、分层大树和镇旁道具则是独立节点。运行时不会再额外生成一套远景。

如果当前阶段主要使用单株手动摆放，请使用 `res://scenes/world/manual_plant_3d.tscn`，放到 `EditableVegetation/EditableManualPlants` 下。完整的贴图制作、导入、替换、风场参数和场景美术编辑步骤见 `res://docs/art/manual-plant-production.md`。

## 实时查看游戏摄像机

打开该场景后可以直接进入实时游戏机位：

1. 在场景树中选择 `EditorGamePreviewRig/EditorGamePreviewCamera`，点击 3D 视窗中的 Camera3D `Preview`，即可使用 Godot 自带的摄像机预览。
2. 刷草时先选择一个草图层，3D 视窗上方会出现 `Game View`；开启后编辑视窗会持续锁定到真实游戏摄像机，同时仍可刷草和选择其他节点。
3. 该视图直接显示当前正在编辑的场景世界，因此移动植物、建筑、道具或灯光后会立即更新，不需要运行游戏。
4. 它与运行时共用同一套摄像机计算，包含 32 度 FOV、72 度俯角、牌桌竖直变换、连续折面、环境光、方向光、植物朝向、风动画和远景景深。
5. 再次点击 `Game View` 可解除锁定并恢复自由查看。

场景树中的 `EditorGamePreviewRig` 用于设置预览：

- `Preview Mode`：切换正常游戏与主菜单取景。
- `Preview Resolution`：目标游戏分辨率，默认 1280×800。
- `Preview Zoom`：游戏中的棋盘缩放。
- `Preview Center Pixels`：游戏逻辑坐标中的镜头中心偏移。
- `Pointer Light Enabled` 与 `Pointer Logical Position`：预览鼠标暖光及其位置。

卡牌、日期和对话框属于运行时的独立 2D 层，不会出现在环境编辑场景中；牌桌、植被、道具、灯光和远景与游戏运行时一致。`Preview Resolution` 决定摄像机按哪种游戏窗口高度计算距离；主编辑视窗的宽高比与该分辨率一致时，四周裁切范围也会一致。

## 手动移动道具

1. 在 Godot 的“文件系统”中双击 `scenes/world/table_environment_editable.tscn`。
2. 展开 `EnvironmentRoot/EditableLandmarks`。
3. 选择树、背包、地图、杯子、灯和较大的近景植物。
4. 使用 3D 编辑器的移动工具调整位置，完成后保存场景。

如果 Godot 在插件加入前已经打开，先执行一次“项目 → 重新加载当前项目”。在场景树中选择某个道具后按 `F`，可以让 3D 视图快速聚焦到牌桌附近。

这些道具都是独立 `Sprite3D` 节点，可以单独移动、缩放、隐藏或复制。人物卡和游戏 UI 不在这张场景中。

远景地标位于 `EnvironmentRoot/EditableDistantLandmarks`，包括分层远景树、城镇、镇旁石块和阔叶植物。远景底图本身是根节点下的 `DistantSkyWorldPlane`。

## 刷植物

工程已启用 `Grass Painter` 编辑器插件。三个可刷图层位于：

- `EnvironmentRoot/EditableVegetation/BroadleafField`
- `EnvironmentRoot/EditableVegetation/RocksField`
- `EnvironmentRoot/EditableVegetation/WhiteFlowersField`
- `EnvironmentRoot/EditableVegetation/FarAncientTreesField`
- `EnvironmentRoot/EditableVegetation/FarBroadleafField`
- `EnvironmentRoot/EditableVegetation/FarWhiteFlowersField`
- `EnvironmentRoot/EditableVegetation/HorizonCrownsField`
- `EnvironmentRoot/EditableVegetation/HorizonTreesField`

选择其中一层后，3D 视口顶部会出现：

- `Grass Brush`：启用画笔。
- `Erase`：擦除模式；画笔模式下按住 `Ctrl` 也可临时擦除。
- `Radius`：画笔半径。
- `Density`：每平方米尝试生成的数量。
- `Spacing`：新实例之间的最小距离。
- `Size Min / Size Max`：随机尺寸范围。
- `Fill`：按当前参数重新填充允许区域。
- `Clear`：清空当前图层。

密集植被使用 MultiMesh，所以不能在视窗里逐株点选。这是部分近景草“点不中”的原因。请先在场景树中选择它所属的图层，再用画笔修改：

1. 选 `BroadleafField` 修改近景大叶草，选 `WhiteFlowersField` 修改近景白花，选 `RocksField` 修改小石块。
2. 点击 `Grass Brush` 开启画笔；左键增加植株。
3. 点击 `Erase` 后左键擦除，或在绘制时按住 `Ctrl` 临时擦除。
4. 精确删除一小片时，把 `Radius` 调到 0.25–0.5 米；单株不能直接框选，但小半径擦除可以达到相同效果。
5. `Density` 控制新增数量，`Spacing` 控制新旧植株最小距离，`Size Min/Max` 控制新刷植株的随机尺寸。
6. `Fill` 会按当前参数重新生成整个图层，`Clear` 会清空整个图层，使用前应确认选中的图层。
7. 完成后关闭 `Grass Brush`，按 `Ctrl+S` 保存场景。

`EditableLandmarks` 与 `EditableDistantLandmarks` 下的树、背包、灯笼、地图、杯子和较大的装饰植物是独立节点，可以直接选择并移动。判断方法很简单：场景树里有独立名字的是单独物体；只显示在某个 `*Field` 图层里的密集草属于画笔实例。

启用 `Grass Brush` 后在折面地形上按住左键绘制。插件会采样牌桌的平面、倒角和后坡，把实例放到对应表面；牌桌和木框范围会被自动排除。所有植被面片会始终平行于编辑器或游戏摄像机，风吹只沿画面左右方向弯曲。编辑器撤销只用于制作场景，不会给游戏增加撤销功能。

运行时继续使用原植被手感：鼠标经过时按完整移动路径影响附近植物，速度越快摆幅越大但有上限；同一区域至少间隔 0.35 秒才允许重播，离开后以 1.1 秒阻尼回弹，避免慢速移动持续抖动。鼠标暖光在植物面片内部逐像素衰减，不会整张植物图片同时亮起或熄灭。

修改完成后按 `Ctrl+S` 保存。不要手动编辑运行时生成的 `__GrassRenderer` 子节点；实例位置保存在所选图层的 `grass_positions` 等场景属性中。

## 更换图层图片

选择一个植被图层，在检查器的 `Visual → Static Texture` 中指定透明背景 PNG。也可以把外部单张图片拖进该属性；插件会复制到 `res://assets/props/grass_types/` 并保持图片比例，不会拉伸到旧图片比例。

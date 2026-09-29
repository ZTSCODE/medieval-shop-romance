# 卡牌交互开源调研

核查日期：2026-09-15。本轮未找到许可可核实、可直接移植的 Stacklands 或 WitchHand 完整游戏源码。[Stacklands 官方仓库](https://github.com/stacklandsdev/mod-template)提供的是模组模板；不能当作游戏本体源码使用。

| 候选 | 已核实版本与许可 | 对本轮的价值 |
|---|---|---|
| [Simple Cards](https://github.com/twdoor/simple-cards-v-2/tree/2d4f0cdc70532949c1fcb3e0db5df6449ff11a4d) | README 声明 Godot 4.5.1+；[MIT 许可](https://github.com/twdoor/simple-cards-v-2/blob/2d4f0cdc70532949c1fcb3e0db5df6449ff11a4d/LICENSE) | 有拖拽、多牌移动与动画；手牌、容器及编辑器功能超出当前需要。 |
| [Deckbuilder Framework](https://github.com/insideout-andrew/deckbuilder-framework/tree/41199fc02c3c9abaae1505737bd9c9080254fe15) | project.godot 声明 4.3；[MIT 许可](https://github.com/insideout-andrew/deckbuilder-framework/blob/41199fc02c3c9abaae1505737bd9c9080254fe15/LICENSE) | 偏向抽牌、洗牌、手牌容器，自由桌面的拆叠、合叠仍需另外实现。 |
| [Godot TopDown Camera2D](https://github.com/cng6sk/Godot-TopDown-Camera2d/tree/43072672963ee4cdcf81d4f98a3dc3f4443831de) | [官方资产库](https://godotengine.org/asset-library/asset/3861)标注 1.2.2 / Godot 4.4；[MIT 许可](https://github.com/cng6sk/Godot-TopDown-Camera2d/blob/43072672963ee4cdcf81d4f98a3dc3f4443831de/LICENSE) | 可参考指针中心缩放、平移及边界处理。 |

上述许可文本允许修改、分发和销售，并要求保留相应版权与许可声明；本轮未运行这些插件验证 4.7.1 兼容性。最终采用自主编写的最小卡牌交互模块，参考通用插值和状态管理思路，没有复制这些第三方源码或引入插件。牌面由 Godot 绘制空白矩形，音效由本项目代码合成，界面使用系统字体，不附带商业游戏图像或字体文件。

Simple Cards 的当前 card.gd 在开始拖动时将抓取偏移改为牌中心，倾斜使用每帧位移；本项目应保留原抓取点，并按时间计算速度与动画。拟采用的动画时长、角度和吸附阈值属于调试初值，不是对原作的实测数据。Godot 自身许可已从本机引擎提取到 `outputs/GODOT_LICENSE.txt`，供后续打包保留。

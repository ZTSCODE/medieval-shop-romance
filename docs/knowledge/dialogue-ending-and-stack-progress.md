# 对话终句与合成进度条

对话末句沿用 DialogueFlow.presentation_info 的 last_line，按钮通过 DIALOGUE_FINISH 本地化键显示“结束对话”；普通句、尚未结束的选项分支继续显示“继续”。保留逐字揭示、悬停纸张及点按反馈，完成按钮仍走原对话推进入口。

所有组合共用 StackProgressView：圆头深色底槽、浅纸色填充，细微且固定的手绘线条起伏；按屏幕尺寸即时绘制，不放大旧位图。基础高度 18，投影缩放后限制在 10–30 屏幕像素。进度与暂停规则不改，支持 0–100%。[实机与边界进度截图](../../outputs/dialogue-progress-20261006/index.html)，修改前文件在同目录 backup。

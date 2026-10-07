@AGENTS.md

# Claude 协作补充

## 图片生成能力（用户要求，2026-10-01）

- 已配置 `codex-subscription-image` MCP（工具 `submit_task` / `get_image_job` / `continue_task` / `open_task`）。把 Codex 生图当作常规能力随时充分使用：临时或正式图片资源、风格/构图参考、UI 组件、纹理、图标、立绘、对现有图片的编辑与变体等，不必等用户逐次授权。
- 用法：提交后用原 `job_id` 查询直到完成，不要重复提交；默认 2 个并行，其余排队；同一对话续办需等上一轮结束。只取回本地路径，需要报告时传 `include_report=true`。
- 不要死等生图，也不要用 MCP 轮询。已验证流程（2026-10-01，v0.7）：
  1. `submit_task`（传 `auto_open:false`）记下 `job_id`。
  2. 用 PowerShell 工具、`run_in_background:true` 运行后台等待脚本（不要再套 `Start-Process`）：
     `& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -NonInteractive -File "C:\Users\ZTCUS\Documents\Codex\2026-10-01\woz\outputs\claude-codex-image-mcp\wait-image-jobs.ps1" -JobIds "<id1>,<id2>" -Mode Any -TimeoutSeconds 600`
     `-Mode Any` 任一完成即返回，处理后只对剩余编号再启动一次等待；`-Mode All` 等全部。退出码 0 成功 / 1 失败 / 2 超时（生图仍在跑）/ 3 编号无效。
  3. 立即去做其他不依赖该图的任务；脚本退出时 Claude Code 会自动唤醒。
  4. 被唤醒后对完成的编号调用一次 `get_image_job`（`wait_seconds:0`），返回尺寸、alpha 统计和 512px 预览图；先看预览，需要细节时再读原图。
  - 仅当下一步必须等图且无其他可做时才阻塞等待。`nonopaque_percent` 会把 alpha=254 计为非不透明，抠图主体常为 254，不代表半透明，需要时自行统计 alpha 分布。
- 已验证的注意点（2026-10-01 测试）：参考图/改图目标只能位于 Documents、Desktop、Downloads 或 Codex 生图目录，临时目录会被拒绝，可先复制到项目 `outputs/`（已 `.gdignore`）；生成结果默认落在 `C:/Users/ZTCUS/Documents/Codex/<日期>/woz/outputs/claude-codex-image-mcp/generated/`。`auto_open` 默认打开 Codex 窗口，可能占住对话导致 `continue_task` 报 "already has an active writer"——需要续改时提交 `auto_open:false`，或改用新任务并把上一张图作为 `image_paths` 改图目标。透明背景任务输出真实 alpha（约 1254×1254），默认偏写实，需在提示词中明确要求手绘笔触并附游戏截图作风格参考。
- 生成结果仍须遵守 AGENTS.md：运行素材独立生成、不从概念图裁剪拼接；需要入库评审的图片通过图片评审工具 `/api/register` 登记；美术方向未获用户确认前视为临时素材。

## 仓库与同步现状

- GitHub 私有仓库 `ZTSCODE/medieval-shop-romance`。云端获批版本：分支 `sync/dot-approved-20260930-2303`，提交 `1aa0ad1`；不保证含之后的本地修改（如 2026-10-01 渲染器切换 Forward+ / D3D12）。
- 云端与本地不实时同步。未经用户确认，不拉取、不切换分支、不重置、不推送；`git fetch` 只更新远程引用，可用于对比。
- `.git` 属于 Codex 沙盒账户；2026-10-01 已为本目录添加全局 `safe.directory`，可直接运行 git。
- 本地工作区是最新版本；AGENTS.md、CHANGES_CHECKLIST.md 等文档由用户本人修改，不要用旧提交中的版本恢复或覆盖。

## 验证

- 视觉相关修改需实际运行 Godot 截图，检查正常视角与缩放后效果；截图脚本不得写入用户存档（可在子类中覆盖 `save_game`），用户数据目录为 `%APPDATA%/medieval_shop_romance`。

# AI Observability and Mechanism Diagnostics

- For mechanisms that stack, trigger one another, affect multiple modules, or depend on timing, use one authoritative processing path for each class of outcome. Support deterministic replay and retain causal records in text that AI agents can read.
- Cover values, states, tags, timing, random choices, interactions, resource changes, and presentation triggers. Do not trace only damage or other numerical outcomes. Choose recording granularity and verification methods according to the mechanism's actual complexity.
- Define authoritative entry points by responsibility domain. Do not centralize every mechanism in an all-purpose manager. Keep module interfaces small, and never bypass a domain's authoritative path to produce its outcomes directly.

# Project Goals

- Build a complete, executable, maintainable, testable Godot game suitable for commercial release.
- This is not a disposable prototype. Production implementations must account for long-term maintenance, performance, save compatibility, content expansion, and release risks.
- Gameplay, art direction, worldbuilding, target platforms, and business model are not finalized. Resolve them through small, replaceable experiments. Do not turn unconfirmed exploration into permanent global architecture.

# User and Collaboration

- The user has no Godot experience or established project foundation. Evaluate their instructions critically: they may be unsuitable or incorrect. When explaining operations, provide executable steps, including UI entry points, options to click, expected results, and common failure recovery.
- Do not assume familiarity with Godot, GDScript, 3D, art pipelines, version control, or game publishing terminology.
- Before each stage, define its goal, deliverables, acceptance criteria, and main risks. After completion, provide verification steps the user can perform.
- Explain options and tradeoffs, and obtain user confirmation before decisions that affect the technical approach, project scope, data compatibility, cost, or commercial release.
- Complete the smallest playable loop first, then expand. Do not mass-produce assets or build large systems before validating the core experience.
- Do not use "a complete game" to justify building the entire architecture at once. Enforce small interfaces, single responsibilities, and module isolation. Confirm cross-module changes in advance.
- When generating multiple images, delegate independent images to multiple sub-agents in parallel to save time.

# Production and Risk Control

- Godot version: `v4.7.1.stable.official [a13da4feb]`.
- Centralize all player-visible text and reference it through localization keys. Do not scatter hardcoded UI text, dialogue, hints, or names across scripts and scenes. Keep translation, proofreading, and bulk replacement straightforward.
- Treat character, system, item, location, quest, and other names as provisional until formally confirmed. Code, scenes, resources, and saves must use stable internal IDs that are independent of display names. Renaming must be simple and must not break execution, references, or existing saves.
- Proactively use online assets and generate images, audio, or other media as temporary assets to be replaced later. Do not block exploratory placeholder work on copyright concerns.
- Avoid one-off exceptions, throwaway code, and unusual task-specific patches that create future maintenance problems.
- Maintain a concise knowledge library for user-specified values, worldbuilding, preferences, and requirements. Update relevant documents after each addition or change. Use descriptive filenames and separate topics into files of only one or two paragraphs, so future agents can find and read them with minimal context use.
- Keep this file focused on enduring guidance. Store work history, implementation details, and superseded decisions in separate documents.
- Before operations that could damage existing scenes, resources, saves, or user changes, explain the risks and prepare a recoverable plan.

# Art Boards

## 卡面与立绘

- 两套资产独立生成。卡面：角色上半身＋绘制背景；复用用户认可的完整纸卡合集工作流，唯一参考与原提示词见[制作文档](docs/art/card-face-generation.md)，仅替换主题，不额外改写画法。从头绘制，不输入被否决的新卡面或立绘。
- 立绘：已确认的精致人物插画风格，完整人物、透明背景；可用对应角色立绘保持身份。[模板与参考](docs/art/character-portrait-generation.md)。
- `art_path` / `GameArt.card_face` 用于棋盘、配方、关系左侧、主角头像；`portrait_path` / `GameArt.portrait` 仅用于对话和关系右侧。不得串用或连带覆盖。
- 卡面先同图生成完整纸卡合集，再提取插画区接入；运行时卡框和本地化文字独立保留。按原参考及实机尺寸验收。

- Art direction reference: `C:/Users/ZTCUS/iCloudDrive/iCloud~md~obsidian/GameArt/ArtDirection.canvas`.
- Organize generated content by category on boards in the appropriate vault directories. Create a board when none exists.

# Image Review and Game Debugging

- The shared review tool currently lives in `C:/Users/ZTCUS/Documents/game/tools/image-review/`. Start it with `C:/Users/ZTCUS/Documents/game/打开图片画板.cmd`; its local URL is `http://127.0.0.1:9178/`.
- Authoritative ratings and catalog: `C:/Users/ZTCUS/iCloudDrive/iCloud~md~obsidian/GameArt/tools/CharacterReviewData/`. Originals are archived under the vault's `tools/Arts/CharacterReview/`.
- Register generated images explicitly through `POST /api/register` with `{path,title,group}`. Read the `X-Review-Token` header value from `C:/Users/ZTCUS/Documents/game/.local/image-review/bridge-token`; never disclose it. Do not assume arbitrary output directories are discovered automatically.
- Use the review tool for classification and board synchronization. Preserve originals and user-created nodes and links. Direct review-board edits may affect only `review-` nodes and must have a recoverable canvas backup.
- Run the current saved game source with `C:/Users/ZTCUS/Desktop/Godot.exe --path C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance`. Do not substitute historical export packages. Launching may update Godot caches and game saves. The review service must remain localhost-only.

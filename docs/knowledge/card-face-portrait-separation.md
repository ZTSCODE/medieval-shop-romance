# 卡面与角色立绘分离

2026-10-04：卡面与角色立绘分别制作；角色卡面采用带背景的上半身构图。棋盘、配方卡牌预览、配方列表、人物关系左侧列表及主角头像均使用卡面；保持原有卡框和玩法。首批细致卡面和随后粗笔触卡通头像均被用户否决。用户要求复用 `outputs/ui-travel-paper-20260919/` 的原提示词和原四张 Book of Travels 参考；来源对话是 `01a0b652-d210-7a82-b9c9-79ed5250570c`「转换人物为参考图风格 (31)」。沿用原 UI 对话的提示词与四张参考，少加额外限制；现版仍被指出细碎，用户改为同一张图生成多张卡面后切分，以统一并概括画法。生成时不输入角色立绘或被否决的卡面，身份仅用文字描述。

对话双方立绘、人物关系右侧详情继续使用原立绘。`GameArt.card_face(subject_id)` 按稳定卡牌 ID、种类或 NPC 的 `card_id` 查找卡面；`GameArt.portrait(subject_id)` 独立读取 `portrait_path`。主角卡牌显式保留 `portrait_path`，避免以后替换卡面连带修改立绘。旧文件和代码备份在 `outputs/painted-card-faces-20261004/backup/`。长期制作规则已写入项目 AGENTS.md，详见 [卡面提示词与原参考](../art/card-face-generation.md) 及 [立绘生成与使用](../art/character-portrait-generation.md)；提示词和四张原参考已归档到 `docs/art/card-face-style/`。


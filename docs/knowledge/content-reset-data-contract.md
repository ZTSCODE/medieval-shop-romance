# 空内容基座数据接口

`data/content.json` 保留 `version`、`content_generation` 以及空 `cards/recipes/npcs/stories/events`。可选 `initial_cards` 为 `{definition_id, position:[x,y], count}` 数组；`opening` 支持 `pages` 本地化键数组、`title_key/tutorial_key`、`initial_cards:[{kind,offset:[x,y],metadata}]` 和 `explore:{required_kinds,consumed_kinds,outputs:[{kind,metadata}],duration}`。空开局配置安全停用；不得添加未登记卡牌。NPC 的 `story_ids`、剧情的 `requires_completed/repeatable` 控制对话选择；`portrait_region:[x,y,w,h]` 控制标准化裁切，`encounter_card_id/encounter_name_key` 控制相遇地点，无配置时不显示。

`runtime_rules` 可配置 `market_unlock_fact/shop_unlock_fact`；`contact_visits` 每项包含完整内部 ID 字段 `permission_fact,interest_facts,visit_story,first_receipt,arrival_fact,visit_operation,return_story,revisit_receipt_prefix`，不再使用旧角色固定映射。以上只是保留机制的数据入口，不是新内容授权；具体角色、剧情、配方与运营规则仍待用户重新确定。更改内容代际必须同时考虑存档隔离与回归验证。

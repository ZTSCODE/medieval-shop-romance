# Narrative audio plan — source-verified opening

Verified 2026-10-06 against current `data/content.json`, `localization/game.csv`, and `data/onboarding_goals.json`. The JSON sibling is the machine-readable authority. Curated sound direction is merged. All finite cue IDs are bound to the curated catalog naming contract; runtime wiring and actual playback are verified by the implementation owner.

## Findings that govern the mix

- Current playable content contains only the Messenger at the wood edge and in the wood: 53 main lines, 8 selected-branch replies, and 6 choices. No active chapter package is present.
- The retained v7 opening film has an embedded score/voice/effects track. Gameplay music and ambience give it exclusive ownership. Subtitle changes never trigger extra literal effects.
- The user explicitly places the opening near the snowline and asks for storm/snow/grass/branch sounds. Use that as weather context. The active first narration says the ground is soft; do not turn its footsteps into deep-snow crunch. Cold wind softens when the trees close.
- The chase and hand-warming dialogue need space and restrained sound. No bright tavern lute, birdsong, continuous barking, or automatic day-cycle music should override the described night.
- Later-scene drafts are excluded. They do not authorize events, ambience, characters, or plot-revealing sounds in the present game.

## Runtime trigger contract

Legacy dialogue uses `presentation_info().marker`: `story_id:zero_based_line_index:branch_choice:branch_index`. Examples: `story.messenger.edge:0::0` and `story.messenger.edge:6:stone:0`. Generic chapter dialogue supports `story_id:node_id`, but chapter content is absent here.

Bind a plan only in `DialogueOverlay.sync()` when the marker changes. A typewriter phrase may release one already-scheduled cue, but must never recreate it per character. Layout, resize, localization refresh, player-name refresh, and choice hover are not line entry. Track each cue once per line visit; pause its clock in menus; discard pending cues when advancing. A new/load session re-establishes the correct environment instead of trusting stale scene state.

Choice labels describe possible actions, not performed ones. Only the selected branch reply makes its matching foley. A report of past events or future instruction is not a current action.

## Audited environmental transitions

### film_to_naming

Trigger: `opening film finished or skipped, opening stage intro completed`.

cold exposed night wind begins only after film gives up audio ownership. Catalog bed: `ambience.snowline`. Music: `silence`.

### edge_enter

Trigger: `story.messenger.edge:0::0`.

exposed cold night; ground soft, pursuer distant. Catalog bed: `ambience.snowline`. Music: `silence`.

### trees_close

Trigger: `story.messenger.edge:3::0`.

sheltered damp foggy wood; wind attenuates. Catalog bed: `ambience.cold_wood`. Music: `silence`.

### stream_instruction

Trigger: `story.messenger.edge:30::0`.

retain wood; only a distant stream may become audible, no entering water yet. Catalog bed: `ambience.cold_wood`. Music: `silence`.

### walk_wood_start

Trigger: `OpeningFlow.work_stack_id() becomes nonempty while stage explore`.

wet blackthorn wood; user follows instructed stream route. Catalog bed: `ambience.hidden_creek`. Music: `silence`.

Bounded actual activity only: `narrative.wet_step`, `narrative.brush_thorns`.

### walk_wood_finish

Trigger: `OpeningFlow.outputs_created/revealed; opening_explored event`.

sheltered wet wood. Catalog bed: `ambience.cold_wood`. Music: `silence`.

### messenger_returns

Trigger: `story.messenger.thorn_rules:0::0`.

sheltered wood one hour later; dogs successfully diverted. Catalog bed: `ambience.cold_wood`. Music: `silence`.

### follow_track_start

Trigger: `actual LocationExploration work starts with hero + badger_track`.

damp woodland track, away from running water. Catalog bed: `ambience.cold_wood`. Music: `music.story`.

Bounded actual activity only: `narrative.soft_steps`, `narrative.brush_thorns`, `narrative.twig_small`.

Twig contact only during real physical exploration, sparse and finite; never on stationary mist/standing stones.

### arrive_stones

Trigger: `explore_completed:card.loc.badger_track and the_stones card created`.

quiet woodland bed retained; stop footsteps. Catalog bed: `ambience.cold_wood`. Music: `music.story`.

No villagers, fire, shop, sunrise birds, stone magic, or future drafted scene audio.

## Every active line and branch

### story.messenger.edge

- `DLG_MESSENGER_EDGE_01` | `story.messenger.edge:0::0` | narrator
  - 肺里像着了火。脚下的地越来越软。身后某处，一条狗叫了一声，又停了。
  - Source: `data/content.json/stories/story.messenger.edge/lines/0`, `localization/game.csv` row ending at line 218.
  - Audio: `ambience.snowline` / `cold_edge`; music `silence`. One finite snow/slush-to-soft-ground step take, exactly one distant rear dog bark; no breath asset added. Cue anchors: narrative.snow_to_soft_ground @ 脚下的地越来越软; narrative.dog_far @ 一条狗叫了一声. Constraint: No cozy music; snowline is latest user direction, dampening ground is exact runtime text.

- `DLG_MESSENGER_EDGE_02` | `story.messenger.edge:1::0` | narrator
  - 树缝里有灯。也可能只是水面映着月亮。你已经分不清了。
  - Source: `data/content.json/stories/story.messenger.edge/lines/1`, `localization/game.csv` row ending at line 219.
  - Audio: `ambience.snowline` / `cold_edge`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_03` | `story.messenger.edge:2::0` | narrator
  - 你的左手抖个不停。你把它塞进外套里按住，像按住别人的手。
  - Source: `data/content.json/stories/story.messenger.edge/lines/2`, `localization/game.csv` row ending at line 220.
  - Audio: `ambience.snowline` / `cold_edge`; music `silence`. one close coat-sleeve movement Cue anchors: narrative.scarf @ 你把它塞进外套里. Constraint: No added heartbeat/magic.

- `DLG_MESSENGER_EDGE_04` | `story.messenger.edge:3::0` | narrator
  - 然后树木合拢过来，一片白雾横在你面前，低低的，一动不动。
  - Source: `data/content.json/stories/story.messenger.edge/lines/3`, `localization/game.csv` row ending at line 221.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. reduce open wind; short damp foliage brush, optional very small twig tick Cue anchors: narrative.brush_thorns @ 然后树木合拢过来. Constraint: Mist and trees are ordinary, no supernatural whoosh or tree collapse.

- `DLG_MESSENGER_EDGE_05` | `story.messenger.edge:4::0` | narrator
  - 前方的雾里有东西在动。你停下。它也停下。
  - Source: `data/content.json/stories/story.messenger.edge/lines/4`, `localization/game.csv` row ending at line 222.
  - Audio: `ambience.cold_wood` / `still_thicket`; music `silence`. brief movement ahead then stop all locomotion gestures Cue anchors: narrative.brush_thorns @ 前方的雾里有东西在动. Constraint: Hold quiet; do not keep hero or stranger footsteps looping.

- `DLG_MESSENGER_EDGE_06` | `story.messenger.edge:5::0` | narrator
  - 一个人那么高的影子。腰间闪过一点黄铜。
  - Source: `data/content.json/stories/story.messenger.edge/lines/5`, `localization/game.csv` row ending at line 223.
  - Audio: `ambience.cold_wood` / `still_thicket`; music `silence`. none Constraint: Glint of brass is visual, not a metal strike.

- `DLG_PROMPT_WHAT_DO_YOU_DO` | `story.messenger.edge:6::0` | hero
  - 你会怎么做？
  - Source: `data/content.json/stories/story.messenger.edge/lines/6`, `localization/game.csv` row ending at line 217.
  - Audio: `ambience.cold_wood` / `still_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_CHOICE_HOLD_STILL_1` | `story.messenger.edge:6:hold_still:0` | narrator
  - 你把自己缩得很小。没什么用。
  - Source: `data/content.json/stories/story.messenger.edge/lines/6/choices/0/lines/0`, `localization/game.csv` row ending at line 225.
  - Audio: `ambience.cold_wood` / `still_thicket`; music `silence`. one faint cloth contraction Cue anchors: narrative.scarf @ 你把自己缩得很小. Constraint: Do not trigger on choice hover.

- `DLG_MESSENGER_EDGE_CHOICE_HOLD_STILL_2` | `story.messenger.edge:6:hold_still:1` | npc
  - 你知道吧，我看得见你。
  - Source: `data/content.json/stories/story.messenger.edge/lines/6/choices/0/lines/1`, `localization/game.csv` row ending at line 226.
  - Audio: `ambience.cold_wood` / `still_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_CHOICE_STONE_1` | `story.messenger.edge:6:stone:0` | narrator
  - 你的手握住一块石头。冰凉，小得派不上用场。
  - Source: `data/content.json/stories/story.messenger.edge/lines/6/choices/1/lines/0`, `localization/game.csv` row ending at line 228.
  - Audio: `ambience.cold_wood` / `still_thicket`; music `silence`. one small stone pickup scrape/contact Cue anchors: narrative.stone_pickup @ 你的手握住一块石头. Constraint: Never a throw or landing impact; do not trigger on choice hover.

- `DLG_MESSENGER_EDGE_CHOICE_STONE_2` | `story.messenger.edge:6:stone:1` | npc
  - 求你别。我今天已经够累了。
  - Source: `data/content.json/stories/story.messenger.edge/lines/6/choices/1/lines/1`, `localization/game.csv` row ending at line 229.
  - Audio: `ambience.cold_wood` / `still_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_CHOICE_CALL_OUT_1` | `story.messenger.edge:6:call_out:0` | npc
  - 一个不值得你扔石头的人。
  - Source: `data/content.json/stories/story.messenger.edge/lines/6/choices/2/lines/0`, `localization/game.csv` row ending at line 231.
  - Audio: `ambience.cold_wood` / `still_thicket`; music `silence`. none Constraint: Spoken mention of throwing is not a throw.

- `DLG_MESSENGER_EDGE_07` | `story.messenger.edge:7::0` | narrator
  - 一个年轻人从雾里走出来，喘着粗气。头发上别着月桂，腰间挎着信包。
  - Source: `data/content.json/stories/story.messenger.edge/lines/7`, `localization/game.csv` row ending at line 232.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Two finite damp approach steps; no breath asset added. Stranger stops once arrived. Cue anchors: narrative.soft_steps @ 从雾里走出来; narrative.soft_steps @ 从雾里走出来 (+0.42s). Constraint: Movement stops once stranger arrives.

- `DLG_MESSENGER_EDGE_08` | `story.messenger.edge:8::0` | npc
  - 哦。不是鹿啊。
  - Source: `data/content.json/stories/story.messenger.edge/lines/8`, `localization/game.csv` row ending at line 233.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_09` | `story.messenger.edge:9::0` | hero
  - 谁派你来的？
  - Source: `data/content.json/stories/story.messenger.edge/lines/9`, `localization/game.csv` row ending at line 234.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_10` | `story.messenger.edge:10::0` | npc
  - 送信的活儿派我来的。没人派我去追人。我跑得不够快，吓不着谁。
  - Source: `data/content.json/stories/story.messenger.edge/lines/10`, `localization/game.csv` row ending at line 235.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_11` | `story.messenger.edge:11::0` | narrator
  - 他越过你，望向你来的方向。笑意淡了些。
  - Source: `data/content.json/stories/story.messenger.edge/lines/11`, `localization/game.csv` row ending at line 236.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_12` | `story.messenger.edge:12::0` | npc
  - 不过，倒是有人派了他们。
  - Source: `data/content.json/stories/story.messenger.edge/lines/12`, `localization/game.csv` row ending at line 237.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_13` | `story.messenger.edge:13::0` | hero
  - 他们？
  - Source: `data/content.json/stories/story.messenger.edge/lines/13`, `localization/game.csv` row ending at line 238.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_14` | `story.messenger.edge:14::0` | npc
  - 那些灯。在河边。雾一起，他们就丢了你的踪迹。天一亮，他们会再找到的。
  - Source: `data/content.json/stories/story.messenger.edge/lines/14`, `localization/game.csv` row ending at line 239.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. optional very distant river bed, otherwise inherit Constraint: River is distant; no player entering water.

- `DLG_MESSENGER_EDGE_15` | `story.messenger.edge:15::0` | narrator
  - 你没有回头。你信不过自己。
  - Source: `data/content.json/stories/story.messenger.edge/lines/15`, `localization/game.csv` row ending at line 240.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_16` | `story.messenger.edge:16::0` | npc
  - 你一直在跑。
  - Source: `data/content.json/stories/story.messenger.edge/lines/16`, `localization/game.csv` row ending at line 241.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_17` | `story.messenger.edge:17::0` | hero
  - 你也是。
  - Source: `data/content.json/stories/story.messenger.edge/lines/17`, `localization/game.csv` row ending at line 242.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_18` | `story.messenger.edge:18::0` | npc
  - 我跑是有工钱的。你看起来像是一停下来就要付出代价。
  - Source: `data/content.json/stories/story.messenger.edge/lines/18`, `localization/game.csv` row ending at line 243.
  - Audio: `ambience.cold_wood` / `sheltered_thicket`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_19` | `story.messenger.edge:19::0` | narrator
  - 他递过来一只水壶，壶身上錾着一对黄铜翅膀。
  - Source: `data/content.json/stories/story.messenger.edge/lines/19`, `localization/game.csv` row ending at line 244.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. dull small flask movement and tiny enclosed slosh Cue anchors: narrative.flask_handover @ 他递过来一只水壶. Constraint: No pouring, uncorking, drinking, toast, or wing sound.

- `DLG_MESSENGER_EDGE_20` | `story.messenger.edge:20::0` | npc
  - 喝吧。还是热的。
  - Source: `data/content.json/stories/story.messenger.edge/lines/20`, `localization/game.csv` row ending at line 245.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. none Constraint: Invitation to drink is not confirmed drinking.

- `DLG_MESSENGER_EDGE_21` | `story.messenger.edge:21::0` | narrator
  - 你接过来。手指冷得厉害，黄铜摸上去竟有点烫。
  - Source: `data/content.json/stories/story.messenger.edge/lines/21`, `localization/game.csv` row ending at line 246.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. one subtle brass flask receiving/contact Cue anchors: narrative.flask_handover @ 你接过来. Constraint: Complement previous handoff rather than replay entire action.

- `DLG_MESSENGER_EDGE_22` | `story.messenger.edge:22::0` | narrator
  - 他注意到了。不等你缩手，他的手就覆上来，连你的手一起握住壶身。
  - Source: `data/content.json/stories/story.messenger.edge/lines/22`, `localization/game.csv` row ending at line 247.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. soft sleeve touch, optional extremely soft flask contact Cue anchors: narrative.scarf @ 他的手就覆上来. Constraint: No bright metal ping.

- `DLG_MESSENGER_EDGE_23` | `story.messenger.edge:23::0` | npc
  - 圣徒在上。你冷得像块冰。
  - Source: `data/content.json/stories/story.messenger.edge/lines/23`, `localization/game.csv` row ending at line 248.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_24` | `story.messenger.edge:24::0` | narrator
  - 他的手带着赶路的热度。他一直握着，直到水壶不再发抖。
  - Source: `data/content.json/stories/story.messenger.edge/lines/24`, `localization/game.csv` row ending at line 249.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. faint rattle, if already present, diminishes and stops Constraint: Silence preferable to a conspicuous invented rattle.

- `DLG_MESSENGER_EDGE_25` | `story.messenger.edge:25::0` | narrator
  - 然后他第一次认真地看你。看你的脸，像是想认出什么。
  - Source: `data/content.json/stories/story.messenger.edge/lines/25`, `localization/game.csv` row ending at line 250.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. none Constraint: Keep gaze/recollection unresolved; no reveal sting.

- `DLG_MESSENGER_EDGE_26` | `story.messenger.edge:26::0` | npc
  - 我们见过吗？
  - Source: `data/content.json/stories/story.messenger.edge/lines/26`, `localization/game.csv` row ending at line 251.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. Retain scene bed; no new literal one-shot.

- `DIALOGUE_CHOOSE_REPLY` | `story.messenger.edge:27::0` | hero
  - 你会怎么说？
  - Source: `data/content.json/stories/story.messenger.edge/lines/27`, `localization/game.csv` row ending at line 27.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_CHOICE_NO_1` | `story.messenger.edge:27:no:0` | npc
  - 嗯。没有。见过的话，我会记得。
  - Source: `data/content.json/stories/story.messenger.edge/lines/27/choices/0/lines/0`, `localization/game.csv` row ending at line 253.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_CHOICE_NOT_SURE_1` | `story.messenger.edge:27:not_sure:0` | npc
  - 那就是你长了一张让人觉得眼熟的脸。
  - Source: `data/content.json/stories/story.messenger.edge/lines/27/choices/1/lines/0`, `localization/game.csv` row ending at line 255.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_CHOICE_PULL_AWAY_1` | `story.messenger.edge:27:pull_away:0` | narrator
  - 他由着你。他没有不高兴，倒像是把什么事默默记下了。
  - Source: `data/content.json/stories/story.messenger.edge/lines/27/choices/2/lines/0`, `localization/game.csv` row ending at line 257.
  - Audio: `ambience.cold_wood` / `quiet_contact`; music `silence`. one sleeve withdrawal Cue anchors: narrative.scarf @ 他由着你. Constraint: No failure/rejection cue.

- `DLG_MESSENGER_EDGE_27` | `story.messenger.edge:28::0` | narrator
  - 远远的身后，狗又叫了。比刚才近。
  - Source: `data/content.json/stories/story.messenger.edge/lines/28`, `localization/game.csv` row ending at line 258.
  - Audio: `ambience.cold_wood` / `renewed_threat`; music `silence`. one rear dog bark from same source family, louder/clearer/drier than 01 Cue anchors: narrative.dog_nearer @ 狗又叫了. Constraint: Still distant; no sudden near-ear bark or roaming stereo.

- `DLG_MESSENGER_EDGE_28` | `story.messenger.edge:29::0` | npc
  - 好。听我的。
  - Source: `data/content.json/stories/story.messenger.edge/lines/29`, `localization/game.csv` row ending at line 259.
  - Audio: `ambience.cold_wood` / `renewed_threat`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_29` | `story.messenger.edge:30::0` | npc
  - 那几棵树后面有条小溪。走在水里，别走岸上，一直走到林子变稀。
  - Source: `data/content.json/stories/story.messenger.edge/lines/30`, `localization/game.csv` row ending at line 260.
  - Audio: `ambience.cold_wood` / `renewed_threat`; music `silence`. none Constraint: Stream route is an instruction, locomotion starts only with real exploration.

- `DLG_MESSENGER_EDGE_30` | `story.messenger.edge:31::0` | hero
  - 那你呢？
  - Source: `data/content.json/stories/story.messenger.edge/lines/31`, `localization/game.csv` row ending at line 261.
  - Audio: `ambience.cold_wood` / `renewed_threat`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_31` | `story.messenger.edge:32::0` | npc
  - 给我一样你贴身穿过的东西。
  - Source: `data/content.json/stories/story.messenger.edge/lines/32`, `localization/game.csv` row ending at line 262.
  - Audio: `ambience.cold_wood` / `renewed_threat`; music `silence`. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_EDGE_32` | `story.messenger.edge:33::0` | narrator
  - 你把围巾递给他。他一句话没说，绕在了自己脖子上。
  - Source: `data/content.json/stories/story.messenger.edge/lines/33`, `localization/game.csv` row ending at line 263.
  - Audio: `ambience.cold_wood` / `renewed_threat`; music `silence`. short soft scarf handoff and wrapping gesture Cue anchors: narrative.scarf @ 你把围巾递给他. Constraint: Cloth not armor; no unexplained fastener.

- `DLG_MESSENGER_EDGE_33` | `story.messenger.edge:34::0` | npc
  - 我带它们往反方向跑一里地，再回来追上你。走。
  - Source: `data/content.json/stories/story.messenger.edge/lines/34`, `localization/game.csv` row ending at line 264.
  - Audio: `ambience.cold_wood` / `awaiting_escape`; music `silence`. none until actual exploration Constraint: Promise to run is not already running; no indefinite chase loop.

### story.messenger.thorn_rules

- `DLG_MESSENGER_RULES_01` | `story.messenger.thorn_rules:0::0` | narrator
  - 一个钟头后，他追了上来，膝盖以下全湿透了，一脸得意。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/0`, `localization/game.csv` row ending at line 265.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `silence`. short approaching wet-boot sequence, light wet clothing Cue anchors: narrative.wet_arrive @ 他追了上来. Constraint: One-hour time jump; no continuous dog chase or exaggerated wading.

- `DLG_MESSENGER_RULES_02` | `story.messenger.thorn_rules:1::0` | npc
  - 它们往反方向去了。狗最爱围巾。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/1`, `localization/game.csv` row ending at line 266.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `silence`. none Constraint: Dogs diverted is a past report; remove dog ambience. Tentative calm theme may fade in after this beat.

- `DLG_MESSENGER_RULES_03` | `story.messenger.thorn_rules:2::0` | narrator
  - 他把围巾还给你。围巾被他的脖子捂得还是暖的。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/2`, `localization/game.csv` row ending at line 267.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. one close soft scarf handback Cue anchors: narrative.scarf @ 他把围巾还给你. Constraint: Do not add romance chime.

- `DLG_MESSENGER_RULES_04` | `story.messenger.thorn_rules:3::0` | npc
  - 好了。既然没人告诉过你，有两件事你得知道。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/3`, `localization/game.csv` row ending at line 268.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_05` | `story.messenger.thorn_rules:4::0` | npc
  - 第一，在背风地，没人问你是从哪儿来的。你也别问他们。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/4`, `localization/game.csv` row ending at line 269.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_06` | `story.messenger.thorn_rules:5::0` | npc
  - 第二，别一个人进村。那里的人见过兵。在路边的立石那儿等我，我带你进去。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/5`, `localization/game.csv` row ending at line 270.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_07` | `story.messenger.thorn_rules:6::0` | narrator
  - 他在一丛黑刺李边蹲下，摘了一颗果子，皱眉看了看，放进你掌心。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/6`, `localization/game.csv` row ending at line 271.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. soft crouch clothing, leaves, tiny berry-stem pluck and handoff Cue anchors: narrative.berry_pluck @ 摘了一颗果子. Constraint: Not breaking a whole branch or eating fruit.

- `DLG_MESSENGER_RULES_08` | `story.messenger.thorn_rules:7::0` | npc
  - 留着。现在还涩。等下过第一场霜，就值点东西了。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/7`, `localization/game.csv` row ending at line 272.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_09` | `story.messenger.thorn_rules:8::0` | hero
  - 背风地是什么地方？
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/8`, `localization/game.csv` row ending at line 273.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_10` | `story.messenger.thorn_rules:9::0` | npc
  - 冬天吞掉他们的城镇以后，逃难的人在这儿停了脚。这么远的地方，帝国懒得来找。看你这样子，正合适。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/9`, `localization/game.csv` row ending at line 274.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_11` | `story.messenger.thorn_rules:10::0` | npc
  - 往北有一条獾踩出来的小路，顺着走就到立石。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/10`, `localization/game.csv` row ending at line 275.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_12` | `story.messenger.thorn_rules:11::0` | hero
  - 你不一起走？
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/11`, `localization/game.csv` row ending at line 276.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_13` | `story.messenger.thorn_rules:12::0` | npc
  - 我跑得快。我先去背风地，告诉他们有人要来。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/12`, `localization/game.csv` row ending at line 277.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_14` | `story.messenger.thorn_rules:13::0` | npc
  - 他们会先让你吃饱，再问你别的。这是规矩。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/13`, `localization/game.csv` row ending at line 278.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_15` | `story.messenger.thorn_rules:14::0` | narrator
  - 他已经倒退着走开了，咧着嘴笑。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/14`, `localization/game.csv` row ending at line 279.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. two soft receding backward footsteps Cue anchors: narrative.soft_steps @ 他已经倒退着走开了; narrative.soft_steps @ 他已经倒退着走开了 (+0.42s). Constraint: Finite gesture.

- `DLG_MESSENGER_RULES_16` | `story.messenger.thorn_rules:15::0` | npc
  - 别一脸担心。你到的时候，我会在那儿。我一向都在。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/15`, `localization/game.csv` row ending at line 280.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. Retain scene bed; no new literal one-shot.

- `DLG_MESSENGER_RULES_17` | `story.messenger.thorn_rules:16::0` | narrator
  - 然后他转身跑进了林子。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/16`, `localization/game.csv` row ending at line 281.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. 3–5 accelerating forest footsteps, brief leaf brush, recede then stop Cue anchors: narrative.run_depart @ 转身跑进了林子. Constraint: No infinite loop, no doorway exit sound.

- `DLG_MESSENGER_RULES_18` | `story.messenger.thorn_rules:17::0` | narrator
  - 你把围巾重新绕回脖子上。上面还有他的体温。
  - Source: `data/content.json/stories/story.messenger.thorn_rules/lines/17`, `localization/game.csv` row ending at line 282.
  - Audio: `ambience.cold_wood` / `sheltered_wood`; music `music.story` at -24.0 dB. one close soft scarf wrap Cue anchors: narrative.scarf @ 你把围巾重新绕回脖子上. Constraint: Physical intimacy through spatial detail, not a reward jingle.

## Choice labels: never literalize until chosen

- `DLG_MESSENGER_EDGE_CHOICE_HOLD_STILL` / `hold_still`: （一动不动。）. Only its selected branch at `story.messenger.edge:6::0` may cue.

- `DLG_MESSENGER_EDGE_CHOICE_STONE` / `stone`: （摸起一块石头。）. Only its selected branch at `story.messenger.edge:6::0` may cue.

- `DLG_MESSENGER_EDGE_CHOICE_CALL_OUT` / `call_out`: “谁在那儿？”. Only its selected branch at `story.messenger.edge:6::0` may cue.

- `DLG_MESSENGER_EDGE_CHOICE_NO` / `no`: “没有。”. Only its selected branch at `story.messenger.edge:27::0` may cue.

- `DLG_MESSENGER_EDGE_CHOICE_NOT_SURE` / `not_sure`: “我不知道。”. Only its selected branch at `story.messenger.edge:27::0` may cue.

- `DLG_MESSENGER_EDGE_CHOICE_PULL_AWAY` / `pull_away`: （把手抽回来。）. Only its selected branch at `story.messenger.edge:27::0` may cue.

## Tutorial and objective text

- `OPENING_HINT_WALK_WOOD`: 把“你”拖到黑刺李林上，走进去。. Display is silent; actual exploration controls footsteps and foliage.

- `OPENING_HINT_MEET_MESSENGER`: 信使追上来了。把“你”拖到他身上。. Display is silent; actual exploration controls footsteps and foliage.

- `OPENING_HINT_FOLLOW_TRACK`: 顺着獾道走：把“你”拖到獾道上。. Display is silent; actual exploration controls footsteps and foliage.

- `ONBOARD_STAGE_INTO_MIST`: 走进雾里. Event: `stage title only`. No narrative foley on display.

- `ONBOARD_GOAL_WALK_WOOD`: 走进黑刺李林. Event: `opening_explored`. No narrative foley on display.

- `ONBOARD_GOAL_MEET_MESSENGER`: 听信使讲讲林子的规矩. Event: `story_completed:story.messenger.thorn_rules`. No narrative foley on display.

- `ONBOARD_GOAL_FOLLOW_TRACK`: 沿着獾道走到立石. Event: `explore_completed:card.loc.badger_track`. No narrative foley on display.

- `ONBOARD_STAGE_TABLE_BASICS`: 熟悉你的桌面. Event: `stage title only`. No narrative foley on display.

- `ONBOARD_GOAL_PAN_TABLE`: 按住右键拖动桌面，四处看看. Event: `camera_panned`. No narrative foley on display.

- `ONBOARD_GOAL_ZOOM_TABLE`: 滚动鼠标滚轮，拉近或拉远. Event: `camera_zoomed`. No narrative foley on display.

- `ONBOARD_GOAL_FOCUS_HERO`: 点击右下角头像，找到自己. Event: `hero_focused`. No narrative foley on display.

- `ONBOARD_STAGE_SHOP_TOOLS`: 打理时间与手账. Event: `stage title only`. No narrative foley on display.

- `ONBOARD_GOAL_CHANGE_TIME`: 点击时间按钮，切换流速. Event: `time_mode_changed`. No narrative foley on display.

- `ONBOARD_GOAL_OPEN_RECIPES`: 翻开配方手账（R）. Event: `journal_recipes_opened`. No narrative foley on display.

- `ONBOARD_GOAL_OPEN_RELATIONSHIPS`: 查看人物关系（N）. Event: `journal_npcs_opened`. No narrative foley on display.

## Film captions: preserve native audio

- `OPENING_FILM_LINE_01` (0.80–3.39s): 很久以前，这片土地上没有国王，

- `OPENING_FILM_LINE_02` (3.80–5.39s): 只有城镇：

- `OPENING_FILM_LINE_03` (6.15–8.40s): 织工的城，铸钟人的城，

- `OPENING_FILM_LINE_04` (8.45–11.05s): 盐商的城，养马人的城。

- `OPENING_FILM_LINE_05` (11.09–16.45s): 每一座都有自己的城墙，每一座都认定自己最好。

- `OPENING_FILM_LINE_06` (17.25–20.50s): 他们为过路钱和界石吵架，

- `OPENING_FILM_LINE_07` (20.54–22.40s): 吵完了又互相嫁娶；

- `OPENING_FILM_LINE_08` (22.44–26.36s): 每到收获的时候，总要去赶彼此的集市。

- `OPENING_FILM_LINE_09` (36.14–40.65s): 后来有一年秋天，雪早早地从北方下来了。

- `OPENING_FILM_LINE_10` (48.74–50.39s): 它盖过了春天，

- `OPENING_FILM_LINE_11` (50.43–52.56s): 又盖过了随后的夏天。

- `OPENING_FILM_LINE_12` (52.60–54.69s): 人们吃掉了种粮，

- `OPENING_FILM_LINE_13` (55.98–57.77s): 然后吃掉了马。

- `OPENING_FILM_LINE_14` (63.68–66.96s): 到第三年，钟已经不再为死者敲响，

- `OPENING_FILM_LINE_15` (67.00–69.36s): 因为死的人太多了。

- `OPENING_FILM_LINE_16` (72.98–76.29s): 就在那一年，运粮的车队从南方来了，

- `OPENING_FILM_LINE_17` (76.33–79.06s): 打着一面谁也没见过的旗。

- `OPENING_FILM_LINE_18` (79.33–84.42s): 哪座城肯打开城门、挂上这面旗，哪座城就有面包吃；

- `OPENING_FILM_LINE_19` (84.88–88.88s): 而每一座开了门的城，都得连钟和种粮一起交出去，

- `OPENING_FILM_LINE_20` (90.38–92.92s): 从此再也养不活自己。

- `OPENING_FILM_LINE_21` (95.09–98.69s): 最后一座不肯低头的城，被攻了下来。

- `OPENING_FILM_LINE_22` (113.31–116.37s): 守城的人被吊死在自家的城墙上，

- `OPENING_FILM_LINE_23` (116.41–120.03s): 城里的人被赶进了雪地。

- `OPENING_FILM_LINE_24` (120.56–123.82s): 帝国就是这样开始的；

- `OPENING_FILM_LINE_25` (123.86–126.24s): 帝国靠这场冬天统治。

- `OPENING_FILM_LINE_26` (126.66–130.17s): 交出儿子、交出劳力的村子，

- `OPENING_FILM_LINE_27` (130.21–131.79s): 粮车会来。

- `OPENING_FILM_LINE_28` (134.63–140.27s): 藏了一把种粮的、跪得慢了的村子，什么也得不到：

- `OPENING_FILM_LINE_29` (140.31–142.25s): 粮车就绕过去，

- `OPENING_FILM_LINE_30` (142.43–145.04s): 剩下的事，交给雪。

- `OPENING_FILM_LINE_31` (148.99–152.41s): 一百年来都是如此。

- `OPENING_FILM_LINE_32` (158.91–162.28s): 可是今夜，帝国每一座城的钟都在响，

- `OPENING_FILM_LINE_33` (163.03–164.97s): 道路全都封了。

- `OPENING_FILM_LINE_34` (165.85–168.87s): 帝国看守的一样东西被人拿走了：

- `OPENING_FILM_LINE_35` (168.91–172.38s): 抵挡白冬的秘密。

- `OPENING_FILM_LINE_36` (172.42–174.66s): 帝国要把它找回来，

- `OPENING_FILM_LINE_37` (174.70–177.04s): 哪怕把每一户人家都翻个底朝天。

## Fallback chronicle pages

Only used when film is disabled or unavailable. They must not sound on top of the native film.

- `OPENING_CHRONICLE_PAGE_1` / `opening:intro:0`: 帝国出现之前，世上没有帝国。 只有一座座自由城镇：各有各的城墙，各有各的田地，各有各的纷争，除了自己，不奉任何人为主。

- `OPENING_CHRONICLE_PAGE_2` / `opening:intro:1`: 然后，白冬来了。春天不化的雪，直到盛夏仍是一片白的田野。 它年复一年向这片土地蔓延，每一年都走得更远一点，夺走得更多一点。

- `OPENING_CHRONICLE_PAGE_3` / `opening:intro:2`: 有一个人看懂了这场冬天能拿来做什么。雪落到哪里，他就带着运粮车和长矛跟到哪里。 饥饿的城镇为面包打开城门，他便把它们的名字写上自己的地图。

- `OPENING_CHRONICLE_PAGE_4` / `opening:intro:3`: 一座又一座，地图被填满了。那人为自己加冕，称帝。 从那以后，白冬一直在为他的家族效力：帝国的粮食到不了的地方，什么也长不出来。

- `OPENING_CHRONICLE_PAGE_5` / `opening:intro:4`: 如今，在那张地图参差的边缘，一个人正在逃命，身后是四十个骑手和他们的猎狗。 他找到了一条线索，指向帝国唯一不能容许的东西：对抗白冬的方法。

## Active location text

- `card.loc.first_forest` / `first_forest`: 黑刺李林 — 又湿又密，够黑，藏得住人。

- `card.loc.badger_track` / `badger_track`: 獾道 — 獾先来的，它们希望你记住这一点。

- `card.loc.the_stones` / `the_stones`: 立石 — 在这儿等他。

## Sources and exclusions

- `scripts/model/dialogue_flow.gd`: active legacy marker and branching contract.
- `scripts/content/module_dialogue_flow.gd`: inactive-module-compatible marker schema.
- `scripts/ui/dialogue_overlay.gd`: true entry gate, typewriter, refresh and layout.
- `scripts/model/opening_flow.gd`: actual first exploration and intro finish.
- `scripts/model/location_exploration.gd`: actual subsequent place exploration.
- `docs/knowledge/opening-film-in-game.md`: embedded-film handoff and fallback.
- `docs/knowledge/opening-pv-score-and-narration.md`: retained v7 and rejected v9.
- `docs/story/opening-cg-film-v4-storyboard.md`: film reference; active timing wins.
- `docs/story/opening-scenes-v2-draft.md` and `docs/story/prologue-outline.md`: unimplemented proposal material, excluded.
- `data/modules/chapter_01/module.json`: absent. Generic code and old tests do not make its prior content active.

## Validation

All 61 active line/branch JSON pointers resolve to the exact text key; all 61 line markers are unique; Chinese prose is nonempty and copied verbatim from active localization. Choice labels, tutorials, objectives, captions, and locations have separate trigger policies.

## Catalog binding and deliberate omissions

There are 22 finite cue instances: 20 physical cue anchors plus the second approach and departure step, each identified independently. Composite walking/running takes are played once. Human breath is omitted because no verified breath asset is supplied. Standstill and recognition lines remain quiet. `music.story` begins only at `DLG_MESSENGER_RULES_03`, after the prior diversion report, at -24 dB. Thin snow/wind belongs to exposed EDGE_01–03; damp sheltered wind takes over at EDGE_04. Running water and wading belong to actual 8-second exploration, never the spoken route instruction.

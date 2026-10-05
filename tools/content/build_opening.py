"""Writes the opening content into data/content.json and its text into localization/game.csv.

English is the source (docs/story/opening-script-draft.md); Chinese follows the glossary in
docs/story/opening-zh-glossary.md. Re-running is safe: our rows are replaced, retired rows removed,
and every other row in the CSV is kept as it was.
"""
import csv
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)

T = {}  # key -> (zh, en)
# Keys from earlier drafts that must not linger in the CSV.
RETIRED = ("DLG_TREELINE_", "DLG_WOODWARD_FIRST_", "DLG_MESSENGER_FIRST_", "CARD_WOODWARD_", "NPC_WOODWARD_",
           "CARD_LUCAN_", "NPC_LUCAN_", "ONBOARD_GOAL_MEET_WOODWARD", "OPENING_HINT_MEET_WOODWARD",
           "OPENING_FOG_", "OPENING_CHRONICLE_", "DLG_MESSENGER_EDGE_", "DLG_MESSENGER_RULES_")


def t(key, zh, en):
    assert key not in T, key
    T[key] = (zh, en)
    return key


# ---------- chronicle: five pages ----------
# Epic register (Absolum / Hades / The Lord of the Rings prologue). One line of conflict:
# a man used the White Winter to swallow the free towns and became Emperor; the winter still serves his house;
# a man on the run at the edge of the map has found a clue to standing against it.
# What the clue is, and who the man is, are set in docs/story/world-bible.md and kept back here.
chronicle = [
    t("OPENING_CHRONICLE_PAGE_1",
      "帝国出现之前，世上没有帝国。\n只有一座座自由城镇：各有各的城墙，各有各的田地，各有各的纷争，除了自己，不奉任何人为主。",
      "Before the Empire, there was no empire.\nThere were the free towns: each with its own walls, its own fields, its own quarrels, and no master but itself."),
    t("OPENING_CHRONICLE_PAGE_2",
      "然后，白冬来了。春天不化的雪，直到盛夏仍是一片白的田野。\n它年复一年向这片土地蔓延，每一年都走得更远一点，夺走得更多一点。",
      "Then came the White Winter. Snow that would not melt in spring. Fields that lay white into midsummer.\nAnd every year it crept a little further across the land, and took a little more."),
    t("OPENING_CHRONICLE_PAGE_3",
      "有一个人看懂了这场冬天能拿来做什么。雪落到哪里，他就带着运粮车和长矛跟到哪里。\n饥饿的城镇为面包打开城门，他便把它们的名字写上自己的地图。",
      "One man understood what the winter was for. Wherever the snow fell, he followed it with grain wagons and spears.\nStarving towns opened their gates for bread, and he wrote their names upon his map."),
    t("OPENING_CHRONICLE_PAGE_4",
      "一座又一座，地图被填满了。那人为自己加冕，称帝。\n从那以后，白冬一直在为他的家族效力：帝国的粮食到不了的地方，什么也长不出来。",
      "Town by town, the map was filled. The man crowned himself Emperor.\nAnd the White Winter has served his house ever since: where the Empire's grain does not go, nothing grows."),
    t("OPENING_CHRONICLE_PAGE_5",
      "如今，在那张地图参差的边缘，一个人正在逃命，身后是四十个骑手和他们的猎狗。\n他找到了一条线索，指向帝国唯一不能容许的东西：对抗白冬的方法。",
      "Now, at the ragged edge of that map, a man runs for his life, with forty riders and their dogs behind him.\nHe has found a clue to the one thing the Empire cannot allow: a way to stand against the White Winter."),
]

t("OPENING_HINT_WALK_WOOD", "把“你”拖到黑刺李林上，走进去。", "Drag yourself onto Blackthorn Wood.")
t("OPENING_HINT_MEET_MESSENGER", "信使追上来了。把“你”拖到他身上。", "The Messenger has caught you up. Drag yourself onto him.")
t("OPENING_HINT_FOLLOW_TRACK", "顺着獾道走：把“你”拖到獾道上。", "Follow the track: drag yourself onto Badger Track.")
t("DLG_PROMPT_WHAT_DO_YOU_DO", "你会怎么做？", "What do you do?")


def lines(prefix, spec):
    """spec items: (speaker, zh, en) or ('choice', prompt_key, [(id, zh, en, [(speaker, zh, en), ...]), ...])."""
    result = []
    n = 0
    for item in spec:
        if item[0] == "choice":
            _, prompt, options = item
            entry = {"speaker": "hero", "text_key": prompt, "choices": []}
            for cid, zh, en, replies in options:
                option = {"id": cid, "text_key": t(f"{prefix}_CHOICE_{cid.upper()}", zh, en), "lines": []}
                for r, (speaker, rzh, ren) in enumerate(replies, 1):
                    option["lines"].append({"speaker": speaker,
                                            "text_key": t(f"{prefix}_CHOICE_{cid.upper()}_{r}", rzh, ren)})
                entry["choices"].append(option)
            result.append(entry)
            continue
        n += 1
        speaker, zh, en = item
        result.append({"speaker": speaker, "text_key": t(f"{prefix}_{n:02d}", zh, en)})
    return result


N, H, NPC = "narrator", "hero", "npc"
REPLY, ACT = "DIALOGUE_CHOOSE_REPLY", "DLG_PROMPT_WHAT_DO_YOU_DO"

# ---------- 1. At the edge of the mist (starts by itself after the pages) ----------
edge = lines("DLG_MESSENGER_EDGE", [
    (N, "肺里像着了火。脚下的地越来越软。身后某处，一条狗叫了一声，又停了。",
        "Your lungs burn. The ground goes soft underfoot, then softer. Somewhere behind you a dog barks once, and stops."),
    (N, "树缝里有灯。也可能只是水面映着月亮。你已经分不清了。", "Lanterns between the trees. Or water catching the moon. You can't tell any more."),
    (N, "你的左手抖个不停。你把它塞进外套里按住，像按住别人的手。",
        "Your left hand won't stop shaking. You push it into your coat and hold it there, as if it belonged to someone else."),
    (N, "然后树木合拢过来，一片白雾横在你面前，低低的，一动不动。", "Then the trees close in, and a bank of white mist lies across your path, low and still."),
    (N, "前方的雾里有东西在动。你停下。它也停下。", "Something moves in the mist ahead. You stop. So does it."),
    (N, "一个人那么高的影子。腰间闪过一点黄铜。", "A shape, man-high. A glint of brass at its belt."),
    ("choice", ACT, [
        ("hold_still", "（一动不动。）", "[Hold still.]",
         [(N, "你把自己缩得很小。没什么用。", "You make yourself very small. It doesn't help."),
          (NPC, "你知道吧，我看得见你。", "I can see you, you know.")]),
        ("stone", "（摸起一块石头。）", "[Pick up a stone.]",
         [(N, "你的手握住一块石头。冰凉，小得派不上用场。", "Your hand closes on a stone. Cold, and too small to matter."),
          (NPC, "求你别。我今天已经够累了。", "Please don't. I've had a long day.")]),
        ("call_out", "“谁在那儿？”", "“Who's there?”",
         [(NPC, "一个不值得你扔石头的人。", "Nobody worth throwing anything at.")]),
    ]),
    (N, "一个年轻人从雾里走出来，喘着粗气。头发上别着月桂，腰间挎着信包。",
        "A young man steps out of the mist, breathing hard. Laurel in his hair, a satchel of letters at his hip."),
    (NPC, "哦。不是鹿啊。", "Oh. You're not a deer."),
    (H, "谁派你来的？", "Who sent you?"),
    (NPC, "送信的活儿派我来的。没人派我去追人。我跑得不够快，吓不着谁。",
          "The post sent me. Nobody sends me after people. I'm not fast enough to be frightening."),
    (N, "他越过你，望向你来的方向。笑意淡了些。", "He looks past you, back the way you came. His smile thins."),
    (NPC, "不过，倒是有人派了他们。", "Someone sent them, though."),
    (H, "他们？", "Them?"),
    (NPC, "那些灯。在河边。雾一起，他们就丢了你的踪迹。天一亮，他们会再找到的。",
          "The lamps. Down by the river. They lost your trail when the mist came up. They'll find it again by first light."),
    (N, "你没有回头。你信不过自己。", "You don't turn round. You don't trust yourself to."),
    (NPC, "你一直在跑。", "You've been running."),
    (H, "你也是。", "So have you."),
    (NPC, "我跑是有工钱的。你看起来像是一停下来就要付出代价。", "I'm paid to. You look like stopping would cost you."),
    (N, "他递过来一只水壶，壶身上錾着一对黄铜翅膀。", "He holds out a flask worked with a pair of brass wings."),
    (NPC, "喝吧。还是热的。", "Drink. It's still warm."),
    (N, "你接过来。手指冷得厉害，黄铜摸上去竟有点烫。", "You take it. Your fingers are so cold the brass almost burns."),
    (N, "他注意到了。不等你缩手，他的手就覆上来，连你的手一起握住壶身。",
        "He notices. Before you can pull away, his hand closes over yours on the flask."),
    (NPC, "圣徒在上。你冷得像块冰。", "Saints. You're freezing."),
    (N, "他的手带着赶路的热度。他一直握着，直到水壶不再发抖。", "His hand is hot from the road. He holds on until the flask stops shaking."),
    (N, "然后他第一次认真地看你。看你的脸，像是想认出什么。", "Then he looks at you properly, for the first time. At your face, as if he were trying to place it."),
    (NPC, "我们见过吗？", "Have we met?"),
    ("choice", REPLY, [
        ("no", "“没有。”", "“No.”",
         [(NPC, "嗯。没有。见过的话，我会记得。", "No. I'd remember.")]),
        ("not_sure", "“我不知道。”", "“I don't know.”",
         [(NPC, "那就是你长了一张让人觉得眼熟的脸。", "Then you've got one of those faces.")]),
        ("pull_away", "（把手抽回来。）", "[Take your hand back.]",
         [(N, "他由着你。他没有不高兴，倒像是把什么事默默记下了。",
             "He lets you. He doesn't look offended. He looks like a man filing something away for later.")]),
    ]),
    (N, "远远的身后，狗又叫了。比刚才近。", "Far behind you, the dogs again. Closer than before."),
    (NPC, "好。听我的。", "Right. Here's what we'll do."),
    (NPC, "那几棵树后面有条小溪。走在水里，别走岸上，一直走到林子变稀。",
          "There's a stream past those trees. Walk in it, not beside it, and keep going until the wood thins."),
    (H, "那你呢？", "And you?"),
    (NPC, "给我一样你贴身穿过的东西。", "Give me something you've been wearing."),
    (N, "你把围巾递给他。他一句话没说，绕在了自己脖子上。", "You hand him your scarf. He winds it round his own neck without a word."),
    (NPC, "我带它们往反方向跑一里地，再回来追上你。走。", "I'll take the dogs a mile the other way, then catch you up. Go."),
])

# ---------- 2. In the wood: the mentor's rules (place You on the Messenger) ----------
rules = lines("DLG_MESSENGER_RULES", [
    (N, "一个钟头后，他追了上来，膝盖以下全湿透了，一脸得意。", "An hour later he catches you up, soaked to the knee and pleased with himself."),
    (NPC, "它们往反方向去了。狗最爱围巾。", "They went the wrong way. Dogs love a scarf."),
    (N, "他把围巾还给你。围巾被他的脖子捂得还是暖的。", "He gives you back your scarf. It is still warm from his neck."),
    (NPC, "好了。既然没人告诉过你，有两件事你得知道。", "So. Two things, since nobody's told you."),
    (NPC, "第一，在背风地，没人问你是从哪儿来的。你也别问他们。",
          "One. In the Lee, nobody asks where you came from. Don't ask them either."),
    (NPC, "第二，别一个人进村。那里的人见过兵。在路边的立石那儿等我，我带你进去。",
          "Two. Don't walk into the village alone. They've had soldiers there before. Wait at the stones by the track, and I'll bring you in."),
    (N, "他在一丛黑刺李边蹲下，摘了一颗果子，皱眉看了看，放进你掌心。",
        "He crouches by a blackthorn, picks a sloe, frowns at it, and drops it into your palm."),
    (NPC, "留着。现在还涩。等下过第一场霜，就值点东西了。", "Keep those. Bitter now. After the first frost, they're worth something."),
    (H, "背风地是什么地方？", "What is the Lee?"),
    (NPC, "冬天吞掉他们的城镇以后，逃难的人在这儿停了脚。这么远的地方，帝国懒得来找。看你这样子，正合适。",
          "A place people stopped running, when the winter took their towns. It's too far out for the Empire to bother with. Which, by the look of you, is the right place."),
    (NPC, "往北有一条獾踩出来的小路，顺着走就到立石。", "North of here there's a badger track. Follow it to the stones."),
    (H, "你不一起走？", "You're not coming?"),
    (NPC, "我跑得快。我先去背风地，告诉他们有人要来。", "I'm faster. I'll run ahead and tell the Lee someone's coming."),
    (NPC, "他们会先让你吃饱，再问你别的。这是规矩。", "They'll feed you before they ask you anything. That's the custom."),
    (N, "他已经倒退着走开了，咧着嘴笑。", "He's already walking backwards, grinning."),
    (NPC, "别一脸担心。你到的时候，我会在那儿。我一向都在。", "Don't look so worried. I'll be there when you arrive. I always am."),
    (N, "然后他转身跑进了林子。", "Then he turns and runs into the trees."),
    (N, "你把围巾重新绕回脖子上。上面还有他的体温。", "You wind the scarf back round your neck. It still holds the warmth of him."),
])

# ---------- cards & people ----------
t("CARD_CHARACTER_CATEGORY", "人物", "Person")
t("CARD_YOU_TITLE", "你", "You")
t("CARD_YOU_DETAIL", "在逃。", "On the run.")
t("CARD_BLACKTHORN_WOOD_TITLE", "黑刺李林", "Blackthorn Wood")
t("CARD_BLACKTHORN_WOOD_DETAIL", "又湿又密，够黑，藏得住人。", "Wet, thorny, and dark enough to hide in.")
t("CARD_MESSENGER_TITLE", "信使", "Messenger")
t("CARD_MESSENGER_DETAIL", "比消息跑得还快。", "Faster than the news.")
t("CARD_SLOES_TITLE", "黑刺李果", "Sloes")
t("CARD_SLOES_DETAIL", "要等霜打过才不涩。", "Bitter until the frost gets to them.")
t("CARD_BADGER_TRACK_TITLE", "獾道", "Badger Track")
t("CARD_BADGER_TRACK_DETAIL", "獾先来的，它们希望你记住这一点。", "The badgers were here first, and would like that remembered.")
t("NPC_MESSENGER_DESCRIPTION", "在背风地和外面之间跑信。认得沼泽里的每一条路。",
  "Runs letters between the Lee and the world outside. Knows every path through the bog.")
t("ONBOARD_STAGE_INTO_MIST", "走进雾里", "Into the Mist")
t("ONBOARD_GOAL_WALK_WOOD", "走进黑刺李林", "Walk into Blackthorn Wood")
t("ONBOARD_GOAL_MEET_MESSENGER", "听信使讲讲林子的规矩", "Hear the Messenger out")
t("ONBOARD_GOAL_FOLLOW_TRACK", "沿着獾道走到立石", "Follow the track to the stones")
t("CARD_STONES_TITLE", "立石", "The Stones")
t("CARD_STONES_DETAIL", "在这儿等他。", "Wait here for him.")

ART = "res://assets/art/opening/"
CHRONICLE_ART = ["chronicle-free-towns.png", "chronicle-3.png", "chronicle-gates.png", "chronicle-5.png", "chronicle-6.png"]
assert len(CHRONICLE_ART) == len(chronicle)


def card(cid, kind, category, name, detail, category_key, art, region, accent, unique=False):
    data = {"id": cid, "kind": kind, "category": category, "name_key": name, "category_key": category_key,
            "detail_key": detail, "accent": accent, "art_path": ART + art, "art_fit": "cover"}
    if region:
        data["art_region"] = region
    if unique:
        data["unique"] = True
    return data


cards = [
    card("card.hero", "hero", "character", "CARD_YOU_TITLE", "CARD_YOU_DETAIL", "CARD_CHARACTER_CATEGORY",
         "hero.png", [0.25, 0.0, 0.5, 0.42], "768caa"),
    card("card.loc.first_forest", "first_forest", "location", "CARD_BLACKTHORN_WOOD_TITLE", "CARD_BLACKTHORN_WOOD_DETAIL",
         "CARD_LOCATION_CATEGORY", "card-blackthorn-wood.png", None, "6f8a78", unique=True),
    card("card.npc.messenger", "messenger", "character", "CARD_MESSENGER_TITLE", "CARD_MESSENGER_DETAIL", "CARD_CHARACTER_CATEGORY",
         "messenger.png", [0.2, 0.0, 0.5, 0.42], "b0703f", unique=True),
    card("card.res.sloes", "sloes", "resource", "CARD_SLOES_TITLE", "CARD_SLOES_DETAIL", "CARD_RESOURCE_CATEGORY",
         "card-sloes.png", None, "7f7aa0"),
    card("card.loc.badger_track", "badger_track", "location", "CARD_BADGER_TRACK_TITLE", "CARD_BADGER_TRACK_DETAIL",
         "CARD_LOCATION_CATEGORY", "card-badger-track.png", None, "8c9670", unique=True),
    card("card.loc.the_stones", "the_stones", "location", "CARD_STONES_TITLE", "CARD_STONES_DETAIL",
         "CARD_LOCATION_CATEGORY", "card-the-stones.png", None, "8f8a80", unique=True),
]
# 通用地点探索：“你”叠在地点上计时，到时产出（scripts/model/location_exploration.gd）。
cards[-2]["explore"] = {"duration": 6.0, "consumes": True, "outputs": [{"kind": "the_stones"}]}

content = {
    "version": 1,
    "content_generation": "reset_20260924",
    "cards": {c["id"]: c for c in cards},
    "recipes": {},
    "npcs": {
        "npc.messenger": {"id": "npc.messenger", "card_id": "card.npc.messenger", "name_key": "CARD_MESSENGER_TITLE",
                          "description_key": "NPC_MESSENGER_DESCRIPTION", "portrait_path": ART + "messenger.png",
                          "story_ids": ["story.messenger.edge", "story.messenger.thorn_rules"]},
    },
    "stories": {
        # scene: 发生在他还没上桌的时候，不需要牌桌上的人物卡，也不能带牌桌后果。
        "story.messenger.edge": {"id": "story.messenger.edge", "npc_id": "npc.messenger", "scene": True,
                                 "npc_hidden_until": 7, "lines": edge},
        "story.messenger.thorn_rules": {"id": "story.messenger.thorn_rules", "npc_id": "npc.messenger",
                                        "requires_completed": ["story.messenger.edge"],
                                        "consequences": ["event.messenger.runs_ahead"], "lines": rules},
    },
    "events": {
        "event.messenger.runs_ahead": {"id": "event.messenger.runs_ahead", "type": "depart_npc", "npc_id": "npc.messenger",
                                       "leave_cards": [{"kind": "badger_track"}]},
    },
    "opening": {
        "pages": chronicle,
        "page_layouts": [{"style": "chronicle", "art": ART + art} for art in CHRONICLE_ART],
        # 序幕之后、林边那段之前请玩家取名（新旅程不在主菜单取名）。
        "name_entry_page": len(chronicle),
        "prologue_story_id": "story.messenger.edge",
        "tutorials": [
            {"key": "OPENING_HINT_WALK_WOOD", "until_stage": "complete"},
            {"key": "OPENING_HINT_MEET_MESSENGER", "until_story": "story.messenger.thorn_rules"},
            {"key": "OPENING_HINT_FOLLOW_TRACK", "until_kind_gone": "badger_track"},
        ],
        "initial_cards": [
            {"kind": "hero", "offset": [-110, 0]},
            {"kind": "first_forest", "offset": [110, 0]},
        ],
        "explore": {
            "required_kinds": ["hero", "first_forest"],
            "consumed_kinds": ["first_forest"],
            "outputs": [
                {"kind": "messenger", "metadata": {"npc_id": "npc.messenger"}},
                {"kind": "sloes"},
            ],
            "duration": 8.0,
        },
    },
    "initial_cards": [],
}

with open("data/content.json", "w", encoding="utf-8", newline="\n") as f:
    json.dump(content, f, ensure_ascii=False, indent=2)
    f.write("\n")

path = "localization/game.csv"
with open(path, encoding="utf-8", newline="") as f:
    raw = f.read()
eol = "\r\n" if "\r\n" in raw else "\n"
rows = [row for row in csv.reader(io.StringIO(raw)) if row and row[0] not in T and not row[0].startswith(RETIRED)]
buf = io.StringIO()
writer = csv.writer(buf, lineterminator=eol)
for row in rows:
    writer.writerow(row)
for key, (zh, en) in T.items():
    writer.writerow([key, zh, en])
with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(buf.getvalue())
print(len(T), "text rows;", len(cards), "cards")

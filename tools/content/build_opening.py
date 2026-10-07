"""Writes the opening content into data/content.json and its text into localization/game.csv.

English is the source (docs/story/opening-script-draft.md). Before changing any text here, read the canon in
docs/story/bible/ (world, places, character cards, style, glossary, continuity); after changing it, update those
files in the same piece of work. Re-running is safe: our rows are replaced, retired rows removed,
and every other row in the CSV is kept as it was. The opening film (opening.film and the OPENING_FILM_* rows)
belongs to build_opening_film.py and is carried over untouched.

After running: Godot --headless --path . --import
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
           "OPENING_FOG_", "OPENING_CHRONICLE_", "DLG_MESSENGER_EDGE_", "DLG_MESSENGER_RULES_", "DLG_HERO_",
           "DLG_MESSENGER_CATCH_", "CARD_SLOES_", "CARD_BADGER_TRACK_", "CARD_STONES_", "OPENING_HINT_FOLLOW_TRACK",
           "ONBOARD_GOAL_FOLLOW_TRACK")


def t(key, zh, en):
    assert key not in T, key
    T[key] = (zh, en)
    return key


# ---------- chronicle: five pages ----------
# Epic register (Absolum / Hades / The Lord of the Rings prologue). One line of conflict:
# a man used the White Winter to swallow the free towns and became Emperor; the winter still serves his house;
# a man on the run at the edge of the map carries something taken from the Empire's keeping.
# These pages are only the fallback for when the opening film is missing; what he took and who he is are kept back
# (docs/knowledge/story-premise.md).
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
      "如今，在那张地图参差的边缘，一个人正在逃命，身后是骑手和他们的猎狗。\n他身上带着一样从帝国手里拿走的东西，帝国非把它找回来不可。",
      "Now, at the ragged edge of that map, a man runs for his life, with riders and their dogs behind him.\nHe carries something taken from the Empire's keeping, and the Empire means to have it back."),
]

t("OPENING_HINT_WALK_WOOD", "把“你”拖到黑刺李林上，走进去。", "Drag yourself onto Blackthorn Wood.")
t("OPENING_HINT_MEET_MESSENGER", "林子里有人。把“你”拖到他身上。", "Someone is in the wood. Drag yourself onto him.")
t("OPENING_HINT_FOLLOW_STREAM", "顺着溪水走：把“你”拖到溪边小道上。", "Follow the stream: drag yourself onto Brookside.")
t("OPENING_HINT_CATCH_UP", "信使追上来了。把“你”拖到他身上。", "The Messenger has caught you up. Drag yourself onto him.")
t("DLG_PROMPT_WHAT_DO_YOU_DO", "你会怎么做？", "What do you do?")


def lines(prefix, spec):
    """spec items: (speaker, zh, en) or ('choice', prompt_key, [(id, zh, en, [(speaker, zh, en), ...]), ...])."""
    result = []
    n = 0
    for item in spec:
        if item[0] == "retired":
            # A line the user cut. Its number stays taken so later keys do not shift, and its row stays in the CSV
            # with empty text so the copy reviewer can still check its history. It is not part of the story.
            n += 1
            t(f"{prefix}_{n:02d}", "", "")
            continue
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

# ---------- 1. Where the snow gives out (the hero alone; starts by itself after the film and the naming) ----------
# He talks to himself. Who he was and what he carries are his secret and are not told here.
# Voice (user, 2026-10-06): a spent man muttering, with breath, sighs and half-finished thoughts; plain lines read flat.
thaw = lines("DLG_HERO_THAW", [
    (H, "哈……哈……不行了。真不行了，一步也走不动了。",
        "Hah… hah… No. No more. Not one more step."),
    (H, "天啊，好累……多久没合眼了？两夜？还是三夜？",
        "God, I'm tired. …How long since I slept? Two nights? Three?"),
    (H, "脚……我已经感觉不到自己的脚了。",
        "My feet… I can't feel my feet any more."),
    (H, "狗叫声也听不见了。也许……跟丢了？不。他们不会停下的。",
        "Can't hear the dogs any more, either. Maybe… they've lost me? No. They won't stop."),
    (H, "……嗯？",
        "…Hm?"),
    (H, "等等。等一下，这是——",
        "Wait. Wait, that's—"),
    (H, "是地。黑泥，枯草，湿头发似的贴在地上。……是草啊。",
        "Ground. Black mud. Dead grass, flat as wet hair. …Grass."),
    (H, "雪……到这儿就停了？不可能。雪从来只进不退。",
        "The snow… it stops here? It can't. The snow never gives ground."),
    (H, "啊……这是什么地方？我到底跑到哪儿来了？",
        "Ah… what is this place? Where have I run to?"),
])

# ---------- 2. The wood comes into view (the forest card has just arrived) ----------
doubt = lines("DLG_HERO_DOUBT", [
    (H, "……树。",
        "…Trees."),
    (H, "这灌木……密得像堵墙，底下黑得像口井。",
        "These thorns… thick as a wall, and black as a well underneath."),
    (H, "马……应该钻不进去吧？狗呢？地这么湿，它们还闻得出我的气味吗？",
        "A horse… couldn't get through that, could it? And the dogs? Ground this wet, could they still pick up my scent?"),
    ("retired",),
    (H, "天知道里头有什么。",
        "God knows what's in there."),
    (H, "不过……要是我能钻进去呢？",
        "Still… what if I could get in?"),
    (H, "说不定，他们就找不着我了。说不定。",
        "They might lose me. They just might."),
    (H, "……怎么样？要不要试一试？",
        "…Well? Do I chance it?"),
])

# ---------- 3. Inside the wood: the Messenger (starts by itself once the wood has been walked) ----------
# The Messenger does not know the hero is hunted (user, 2026-10-06): to him this is a traveller in trouble who has
# walked out of the snow. Only the hero is afraid of who might be behind him, and nothing in the scene proves him right.
edge = lines("DLG_MESSENGER_EDGE", [
    (N, "你拨开刺枝钻了进去。脚下的地越来越软。身后某处，一根树枝咔地断了。你屏住呼吸，直到确定那只是树皮冻裂的声音。",
        "You push in through the thorn. The ground goes soft underfoot, then softer. Somewhere behind you a branch cracks. You stop breathing until you are sure it was only bark splitting in the frost."),
    (N, "树缝里有光。是灯，还是水面映着月亮？你已经分不清了。", "Light between the trees. Lanterns, or water catching the moon? You can't tell any more."),
    (N, "你的左手抖个不停。你把它塞进外套里按住，像按住别人的手。",
        "Your left hand won't stop shaking. You push it into your coat and hold it there, as if it belonged to someone else."),
    (N, "然后树木合拢过来，一片白雾横在你面前，低低的，一动不动。", "Then the trees close in, and a bank of white mist lies across your path, low and still."),
    (N, "前方的雾里有东西在动。你停下。它也停下。", "Something moves in the mist ahead. You stop. So does it."),
    (N, "一个人那么高的影子。腰间闪过一点黄铜。", "A shape, man-high. A glint of brass at its belt."),
    ("choice", ACT, [
        ("hold_still", "一动不动。", "Hold still.",
         [(N, "你把自己缩得很小。没什么用。", "You make yourself very small. It doesn't help."),
          (NPC, "你知道吧，我看得见你。", "I can see you, you know.")]),
        ("stone", "摸起一块石头。", "Pick up a stone.",
         [(N, "你的手摸到一块石头，攥紧了。", "Your hand finds a stone and closes on it."),
          (NPC, "求你别。我今天已经够累了。", "Please don't. I've had a long day.")]),
        ("call_out", "“谁在那儿？”", "“Who's there?”",
         [(NPC, "一个不值得你扔石头的人。", "Nobody worth throwing anything at.")]),
    ]),
    (N, "一个年轻人从雾里走出来，喘着粗气。头发上别着月桂，腰间挎着信包。",
        "A young man steps out of the mist, breathing hard. Laurel in his hair, a satchel of letters at his hip."),
    (NPC, "哦。不是鹿啊。", "Oh. You're not a deer."),
    (H, "谁派你来的？", "Who sent you?"),
    (NPC, "派我？大概是送信这份差事吧。信又不会自己走路，真可惜。",
          "Sent me? The post, I suppose. Letters don't walk by themselves, more's the pity."),
    (N, "他把你打量了一遍：头发上的霜，靴子的惨状。笑意收了些，换成一种小心。",
        "He looks you over: the frost in your hair, the state of your boots. His smile thins into something more careful."),
    (NPC, "你是从雪里走出来的？靠两条腿？", "You've come out of the snow? On foot?"),
    (H, "……那又怎样？", "…What of it?"),
    (NPC, "不怎样。只是从那边来的人，多半走不到这儿。", "Nothing of it. Only that people who come that way don't usually arrive."),
    (N, "他等着你往下说。可你没有接下去。", "He waits for you to go on, but you leave it there."),
    (NPC, "迷路了？", "Lost?"),
    (H, "……差不多吧。", "…Something like that."),
    (NPC, "啊，那正好。找到这地方最好的法子就是迷路。没人是特意来的。",
          "Ah, well. Best way to find the place. Nobody gets here on purpose."),
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
         [(NPC, "嗯……那大概是我认错人了。", "Hm… no, I suppose not. My mistake.")]),
        ("not_sure", "“我不知道。”", "“I don't know.”",
         [(NPC, "不知道？行吧，你想留点神秘，那就留着。", "You don't know? All right. Keep your mystery, then.")]),
        ("pull_away", "把手抽回来。", "Take your hand back.",
         [(N, "他由着你，也没有不高兴，只是把自己的手收了回去。",
             "He lets you. He doesn't seem to mind; he just takes his own hand back.")]),
    ]),
    (N, "你回头望向来的方向。只有树，和树后面的一片白。", "You look back the way you came. Only trees, and the white beyond them."),
    (NPC, "在等人？", "Expecting company?"),
    (H, "没有。", "No."),
    (NPC, "那就好。我只有这一只水壶。", "Good. I've only the one flask."),
    (NPC, "好了。你不能在这儿过夜，就算在雪线这一边，夜里的寒气也要人命。前面不远就有个叫背风地的村子。",
          "Right. You can't sleep out here. The cold comes down at night even this side of the snow. Not far on there's a village called the Lee."),
    (NPC, "我得先给烧炭的老芬恩送封信。你顺着溪水的方向走，走不出一里地我就追上你。",
          "I've a letter for old Finn the charcoal-burner first. Keep to the way the stream runs, and I'll catch you up before you've gone a mile."),
    (N, "你还没来得及说你什么都没答应，他已经消失在树丛里了。水壶还在你手里。",
        "He is gone between the trees before you can say you never agreed to anything. You are still holding his flask."),
])

# ---------- 4. By the stream: he catches you up (place You on the Messenger when he comes back) ----------
# Setting behind this scene (user, 2026-10-06), none of which is to be SAID by anyone:
# the people of the Lee are locals; the winter has simply not spread this far, and much of the south has no snow,
# so to them it is ordinary; they are afraid of the Empire finding the place; the Messenger thinks the hero is a
# traveller in trouble and only learns here that he has nowhere to go. The lines should show these things in how
# the two men behave. No taunts, no boasting, no explaining. See docs/knowledge/story-premise.md.
# He shows the hero the Lee and they finally trade names. {name} is the name the player chose
# (replaced when shown, see scripts/services/player_name_text.gd). His name is Oisín (Irish, "little deer": the first thing
# he says to the hero is "You're not a deer"); provisional until the user confirms it.
catch = lines("DLG_MESSENGER_CATCH", [
    (N, "不到一个钟头，他追了上来，膝盖以下全湿透了，一脸得意。", "Within the hour he catches you up, soaked to the knee and pleased with himself."),
    (NPC, "你在这儿啊。冻成那样的人，走得倒不慢。", "There you are. You walk fast, for a man in that state."),
    (N, "前面的树稀了。树后面升着炊烟，炊烟底下是一片屋顶。", "Ahead the trees thin. Beyond them smoke is rising, and under the smoke there are roofs."),
    (NPC, "看见了吧。那就是背风地。", "There. That's the Lee."),
    (H, "这儿……为什么没有雪？", "Why… is there no snow here?"),
    (NPC, "雪？还没到这儿呢。", "Snow? It hasn't come this far yet."),
    (NPC, "再往南走，一辈子没见过雪的人多的是。", "Go further south and there are plenty of folk who've never seen it in their lives."),
    (N, "你低头看着脚下的泥地，半天没有说话。", "You look down at the bare mud under your feet, and for a long moment you say nothing."),
    (NPC, "走吧。再往前一点，草是绿的。", "Come on. A little further on, the grass is green."),
    (NPC, "不过你别一个人进村。大家都怕帝国找到这儿，冷不丁见了生面孔会慌。跟着我走。", "Only don't walk in on your own. Everyone's afraid of the Empire finding this place, and a strange face out of nowhere would frighten them. Stay with me."),
    (N, "他迈开步子，又猛地站住，你差点撞到他背上。他转过身，一只手扶住你的胳膊，就那么搭着没拿开。",
        "He sets off, then stops so suddenly that you nearly walk into his back. He turns, catches your arm to steady you, and leaves his hand there."),
    (NPC, "圣徒在上。我跟你说了这么半天，连你叫什么都没问。", "Saints. I've been talking at you all this while and never asked your name."),
    # Three different ways of answering his closeness: stay, push back, step away. He reads none of them.
    # (The third option keeps the id "silent" so its text keys and review history stay attached.)
    ("choice", REPLY, [
        ("tell", "告诉他你的名字。", "Tell him your name.",
         [(H, "{name}。", "{name}."),
          (NPC, "{name}……好听。人也好看。", "{name}… I like it. You're good-looking, too."),
          (NPC, "我叫奥辛。", "I'm Oisín."),
          (N, "他的手还搭在你胳膊上。隔着袖子，你也觉得出那只手是热的。",
              "His hand is still on your arm. Even through the sleeve you can feel the heat of it.")]),
        ("you_first", "“你先说。”", "“You first.”",
         [(NPC, "行，那我先来。奥辛。", "All right, me first. Oisín."),
          (N, "他说着凑过来，离你的脸不到一掌远，认认真真地看。",
              "As he says it he leans in, a hand's breadth from your face, and looks at you in earnest."),
          (NPC, "怪了。我还是觉得在哪儿见过你。", "Odd. I still think I've seen you somewhere."),
          (H, "{name}。", "{name}."),
          (NPC, "{name}……没听过。那就是真没见过。", "{name}… No, never heard it. So I haven't, then."),
          (N, "他这才直起身来。", "Only then does he straighten up.")]),
        ("silent", "往后退半步。", "Step back half a pace.",
         [(N, "你往后退了半步。他跟着迈上来半步，手还搭在你胳膊上。",
              "You step back half a pace. He steps forward half a pace after you, his hand still on your arm."),
          (NPC, "嗯？怎么了，站不稳？", "Hm? What is it, are your legs going?"),
          (H, "……{name}。", "…{name}."),
          (NPC, "{name}。我叫奥辛。……你耳朵都冻红了。", "{name}. I'm Oisín. …Your ears have gone red with the cold."),
          (N, "他伸出两只手，把你的耳朵捂住了。", "He puts up both hands and covers your ears.")]),
    ]),
    (N, "你们沿着溪水并排走了一段。", "For a while you walk side by side along the stream."),
    (NPC, "到了村里，你要找谁？", "Who is it you're looking for, in the village?"),
    (H, "……不找谁。", "…No one."),
    (NPC, "那是路过？往南去？", "Passing through, then? Heading south?"),
    (N, "你想了想南边。关于南边，你什么也不知道。", "You think about the south. You know nothing at all about the south."),
    (H, "我没有要去的地方。", "I've nowhere I'm going."),
    (N, "他没有马上说话。有一阵子，只听得见溪水。", "He doesn't speak at once. For a while there is only the sound of the stream."),
    (NPC, "磨坊后头有间屋子，空了两年了。屋顶漏雨，门倒还结实。", "There's a house behind the mill that's stood empty two years. The roof lets the rain in. The door's sound, though."),
    (NPC, "你要是不嫌弃，先住那儿。别的，等你睡够了再说。", "If you can put up with it, stay there for now. The rest can wait until you've slept."),
    (N, "你跟着他，朝炊烟走去。", "You follow him toward the smoke."),
])

# ---------- cards & people ----------
t("CARD_CHARACTER_CATEGORY", "人物", "Person")
t("CARD_YOU_TITLE", "你", "You")
t("CARD_YOU_DETAIL", "在逃。", "On the run.")
t("CARD_BLACKTHORN_WOOD_TITLE", "黑刺李林", "Blackthorn Wood")
t("CARD_BLACKTHORN_WOOD_DETAIL", "又湿又密，够黑，藏得住人。", "Wet, thorny, and dark enough to hide in.")
t("CARD_MESSENGER_TITLE", "信使", "Messenger")
t("CARD_MESSENGER_DETAIL", "比消息跑得还快。", "Faster than the news.")
# Three lines of the old second scene were being reviewed when that scene was rewritten. Their rows stay in the CSV,
# empty, only so the copy reviewer can record that they were removed. They are not part of any story.
for key in ("DLG_MESSENGER_RULES_03", "DLG_MESSENGER_RULES_04", "DLG_MESSENGER_RULES_05"):
    t(key, "", "")

# The seed the hero took. It is on the table from the first moment and nothing in the opening explains it.
# Name (user, 2026-10-06): wants story and suspense; "那一把种子 / A Handful" was rejected as weak.
t("CARD_SEED_TITLE", "老妇的种子", "Her Seed")
t("CARD_SEED_DETAIL", "人人都说它是她的。全国的路都为它封了。", "They say it is hers. Every road in the country is closed for it.")
t("CARD_STREAM_PATH_TITLE", "溪边小道", "Brookside")
t("CARD_STREAM_PATH_DETAIL", "顺着水走，迟早走到有人的地方。", "Follow water and you come to people, sooner or later.")
t("CARD_THE_LEE_TITLE", "背风地", "The Lee")
t("CARD_THE_LEE_DETAIL", "雪还没有到过这里。", "The snow has not reached it. Not yet.")
t("NPC_MESSENGER_DESCRIPTION", "在背风地和外面之间跑信。认得沼泽里的每一条路。",
  "Runs letters between the Lee and the world outside. Knows every path through the bog.")
t("ONBOARD_STAGE_INTO_MIST", "走进林子", "Into the Wood")
t("ONBOARD_GOAL_WALK_WOOD", "把“你”拖到黑刺李林上", "Drag yourself onto Blackthorn Wood")
t("ONBOARD_GOAL_DRAG_CARD", "左键拖动单张卡牌，右键拖动整个组合", "Left-drag one card; right-drag a whole stack")
t("ONBOARD_GOAL_MEET_MESSENGER", "和林子里的人说话", "Talk to the man in the wood")
t("ONBOARD_GOAL_FOLLOW_STREAM", "沿着溪边小道走", "Follow the brookside path")
t("ONBOARD_GOAL_HEAR_LEE", "听信使讲讲背风地", "Hear about the Lee")

ART = "res://assets/art/opening/"
CARD_ART = "res://assets/art/cards/painted_20261004/"
CHRONICLE_ART = ["chronicle-free-towns.png", "chronicle-3.png", "chronicle-gates.png", "chronicle-5.png", "chronicle-6.png"]
assert len(CHRONICLE_ART) == len(chronicle)


# 卡面（art_path）和对话立绘（portrait_path）是两套独立素材，见 docs/knowledge/card-face-portrait-separation.md。
def card(cid, kind, category, name, detail, category_key, accent, unique=False, person=False, portrait=None):
    data = {"id": cid, "kind": kind, "category": category, "name_key": name, "category_key": category_key,
            "detail_key": detail, "accent": accent, "art_path": CARD_ART + kind + ".png"}
    if portrait:
        data["portrait_path"] = ART + portrait
    if person:
        data["art_is_portrait"] = False
    data["art_fit"] = "cover"
    if person:
        data["art_region"] = [0.0, 0.0, 1.0, 1.0]
    if unique:
        data["unique"] = True
    return data


cards = [
    card("card.hero", "hero", "character", "CARD_YOU_TITLE", "CARD_YOU_DETAIL", "CARD_CHARACTER_CATEGORY",
         "768caa", person=True, portrait="hero.png"),
    card("card.loc.first_forest", "first_forest", "location", "CARD_BLACKTHORN_WOOD_TITLE", "CARD_BLACKTHORN_WOOD_DETAIL",
         "CARD_LOCATION_CATEGORY", "6f8a78", unique=True),
    card("card.npc.messenger", "messenger", "character", "CARD_MESSENGER_TITLE", "CARD_MESSENGER_DETAIL", "CARD_CHARACTER_CATEGORY",
         "b0703f", unique=True, person=True),
    card("card.res.winter_seed", "winter_seed", "resource", "CARD_SEED_TITLE", "CARD_SEED_DETAIL", "CARD_RESOURCE_CATEGORY",
         "b89a54", unique=True),
    card("card.loc.stream_path", "stream_path", "location", "CARD_STREAM_PATH_TITLE", "CARD_STREAM_PATH_DETAIL",
         "CARD_LOCATION_CATEGORY", "6f8fa0", unique=True),
    card("card.loc.the_lee", "the_lee", "location", "CARD_THE_LEE_TITLE", "CARD_THE_LEE_DETAIL",
         "CARD_LOCATION_CATEGORY", "a08a6c", unique=True),
]
MESSENGER_CARD = {"kind": "messenger", "metadata": {"npc_id": "npc.messenger"}}
# 通用地点探索：“你”叠在地点上计时，到时产出（scripts/model/location_exploration.gd）。
# 溪边小道：信使还站在桌上时走不了（得先和他说完话，他先走）；走完以后他追上来，背风地出现在眼前。
cards[-2]["explore"] = {"duration": 6.0, "consumes": True, "blocked_by": ["messenger"],
                        "outputs": [MESSENGER_CARD, {"kind": "the_lee"}]}

THAW, DOUBT, EDGE = "story.hero.thaw_edge", "story.hero.wood_doubt", "story.messenger.edge"
CATCH, GOES_AHEAD = "story.messenger.catch_up", "event.messenger.goes_ahead"
with open("data/content.json", encoding="utf-8") as f:
    film = json.load(f).get("opening", {}).get("film")

content = {
    "version": 1,
    # 存档按这个标记分目录存放（saves/<标记>/），标记不同的旧档不会被读取，也不会被覆盖。
    # 只要删掉或改名了卡牌、剧情、事件（旧存档里会出现游戏已经不认识的东西），就必须换一个新标记；
    # 否则旧的自动存档读不出来，游戏又不肯覆盖它，“新旅程”会卡在存档页（2026-10-06 出过这个问题）。
    "content_generation": "opening_20261006",
    "cards": {c["id"]: c for c in cards},
    "recipes": {},
    "npcs": {
        "npc.messenger": {"id": "npc.messenger", "card_id": "card.npc.messenger", "name_key": "CARD_MESSENGER_TITLE",
                          "description_key": "NPC_MESSENGER_DESCRIPTION", "portrait_path": ART + "messenger.png",
                          "story_ids": [EDGE, CATCH]},
    },
    "stories": {
        # solo: 主角的独白，不属于任何人物。
        THAW: {"id": THAW, "npc_id": "", "solo": True, "lines": thaw},
        DOUBT: {"id": DOUBT, "npc_id": "", "solo": True, "requires_completed": [THAW], "lines": doubt},
        # 林中相遇：把“你”拖到信使身上开始；说完他先去送信（卡离桌，之后还会回来）。
        EDGE: {"id": EDGE, "npc_id": "npc.messenger", "npc_hidden_until": 7, "consequences": [GOES_AHEAD], "lines": edge},
        # 溪边：他追上来，介绍背风地，两人互通姓名；说完他留在桌上。
        CATCH: {"id": CATCH, "npc_id": "npc.messenger", "requires_completed": [EDGE], "lines": catch},
    },
    "events": {
        # returns: 只是暂时走开，不算这个人物已经离开。
        GOES_AHEAD: {"id": GOES_AHEAD, "type": "depart_npc", "npc_id": "npc.messenger", "returns": True},
    },
    "opening": {
        "pages": chronicle,
        "page_layouts": [{"style": "chronicle", "art": ART + art} for art in CHRONICLE_ART],
        # 序幕（开场动画）之后请玩家取名（新旅程不在主菜单取名）。
        "name_entry_page": len(chronicle),
        # 自己开始的剧情，按顺序：雪线边的独白 → （林子出现）→ 对林子的犹豫。之后的剧情都要玩家把“你”拖到人或地点上。
        "scenes": [
            {"story": THAW},
            {"story": DOUBT},
        ],
        "tutorials": [
            {"key": "OPENING_HINT_WALK_WOOD", "after_story": DOUBT, "until_stage": "complete"},
            {"key": "OPENING_HINT_MEET_MESSENGER", "until_story": EDGE},
            {"key": "OPENING_HINT_FOLLOW_STREAM", "until_kind_gone": "stream_path"},
            {"key": "OPENING_HINT_CATCH_UP", "until_story": CATCH},
        ],
        # 开局牌桌上是主角和他带着的那把种子（offset 相对镜头正对的桌面中央）；
        # 其余的卡等对应剧情读完才上桌，offset 相对主角的卡。
        "initial_cards": [
            {"kind": "winter_seed", "offset": [-304, -118]},
            {"kind": "hero", "offset": [-84, -118]},
        ],
        "arrivals": [
            {"kind": "first_forest", "after_story": THAW, "offset": [220, 0]},
        ],
        # 走进林子：林子用掉，信使和溪边小道出现。
        "explore": {
            "required_kinds": ["hero", "first_forest"],
            "consumed_kinds": ["first_forest"],
            "outputs": [MESSENGER_CARD, {"kind": "stream_path"}],
            "duration": 8.0,
        },
    },
    "initial_cards": [],
}

if film:
    content["opening"]["film"] = film
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

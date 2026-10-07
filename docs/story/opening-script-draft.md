# Opening Script Draft v1.8

v1.8 (2026-10-06 evening, user): the seed the hero took is a card on the table from the first moment ("Her Seed" / 那一把种子) and is never explained in the opening. Walking the wood brings the Messenger's card and the Brookside path; the meeting is started by the player, and when it ends his card leaves. Walking the path brings him back together with the Lee, and the second talk shows the Lee and has them trade names (he is Oisín / 奥辛, provisional). The sloes, the badger track and the standing stones are gone.

v1.7 (2026-10-06, user): after the film and the naming, the game starts with the hero alone, talking to himself where the snow gives out; the wood is the first card to arrive; he hesitates over it; then the first goals (basic controls and dragging himself onto the wood). The Messenger is met inside the wood, not before it. The hero's past and what he carries are his secret and are not told here (`docs/knowledge/story-premise.md`).

Status: **in the game** (2026-10-03) as temporary content, awaiting user review. English is the source; the Chinese sits beside it in `tools/content/build_opening.py`, which writes `data/content.json` and `localization/game.csv` (glossary: `opening-zh-glossary.md`). The script below is regenerated from that data, so edit the generator, not this file. Setting: `world-bible.md`. Method: `narrative-methodology.md`. Implementation: `docs/knowledge/opening-story-runtime.md`.

User direction (2026-10-03): first a ceremonial chronicle with a sense of history that sets out the world's central conflict (after Absolum's intro); then the hero's own pages have **only the hero**: the tension and suspicion of the flight, no exposition. The person the hero talks to is **the Messenger**, the player's mentor; the hero's situation and the world come out through that conversation. No Warden.

## Flow

| # | Beat | Player does | Cards after |
|---|---|---|---|
| 1 | The opening film (the five chronicle pages are the fallback) | Watches, or holds to skip | (You wait under the dark) |
| 2 | Name the hero | Types a name | **You** |
| 3 | Where the snow gives out: he talks to himself | Reads | You, Her Seed, then **Blackthorn Wood** arrives |
| 4 | The wood: he hesitates | Reads | You, Her Seed, Blackthorn Wood |
| 5 | First goals: look around, zoom, drag one card, walk the wood | Drag You onto Blackthorn Wood (≈8 s) | You, Her Seed, **Messenger**, **Brookside** |
| 6 | Inside the wood: a shape in the mist is the Messenger | Drag You onto the Messenger; reads, two choices | You, Her Seed, Brookside (his card leaves) |
| 7 | Follow the stream | Drag You onto Brookside (≈6 s; not possible while he is still there) | You, Her Seed, **Messenger**, **The Lee** |
| 8 | He catches up: the Lee, and names | Drag You onto the Messenger; reads, one choice | You, Her Seed, Messenger, The Lee |

Format: `NARRATOR`, `YOU` (shows the player's chosen name), `MESSENGER`. `▸` marks a choice; italics are the prompt.

## 1. Chronicle (full screen, five pages)

Epic register in the line of Absolum, Hades and the prologue of The Lord of the Rings; Western, never Chinese-historical. One line of conflict: a man used the White Winter to swallow the free towns one by one and crowned himself Emperor; the winter still creeps and still serves his house; at the ragged edge of the map a man runs because he has found a clue to standing against it. What the clue is and who he is: `world-bible.md` §7, kept back.

> **I**
> Before the Empire, there was no empire.
> There were the free towns: each with its own walls, its own fields, its own quarrels, and no master but itself.

> **II**
> Then came the White Winter. Snow that would not melt in spring. Fields that lay white into midsummer.
> And every year it crept a little further across the land, and took a little more.

> **III**
> One man understood what the winter was for. Wherever the snow fell, he followed it with grain wagons and spears.
> Starving towns opened their gates for bread, and he wrote their names upon his map.

> **IV**
> Town by town, the map was filled. The man crowned himself Emperor.
> And the White Winter has served his house ever since: where the Empire's grain does not go, nothing grows.

> **V**
> Now, at the ragged edge of that map, a man runs for his life, with riders and their dogs behind him.
> He carries something taken from the Empire's keeping, and the Empire means to have it back.

After the last page the game asks for the player's name (no cancel).

## 1a. Where the snow gives out: `story.hero.thaw_edge` (the hero alone; starts by itself after naming; only his card is on the table)

YOU: Hah… hah… No. No more. Not one more step.

YOU: God, I'm tired. …How long since I slept? Two nights? Three?

YOU: My feet… I can't feel my feet any more.

YOU: Can't hear the dogs any more, either. Maybe… they've lost me? No. They won't stop.

YOU: …Hm?

YOU: Wait. Wait, that's—

YOU: Ground. Black mud. Dead grass, flat as wet hair. …Grass.

YOU: The snow… it stops here? It can't. The snow never gives ground.

YOU: Ah… what is this place? Where have I run to?

*(Blackthorn Wood slides onto the table beside him: the first card to arrive.)*

## 1b. The wood: `story.hero.wood_doubt` (the hero alone; starts by itself once the card has landed)

YOU: …Trees.

YOU: These thorns… thick as a wall, and black as a well underneath.

YOU: A horse… couldn't get through that, could it? And the dogs? Ground this wet, could they still pick up my scent?

YOU: God knows what's in there.

YOU: Still… what if I could get in?

YOU: They might lose me. They just might.

YOU: …Well? Do I chance it?

*(The goals panel opens: look around, zoom, drag yourself onto Blackthorn Wood.)*

## 2. Inside the wood: `story.messenger.edge` (drag You onto the Messenger; his portrait stays hidden until he steps out; when it ends his card leaves the table)

The Messenger does not know the hero is hunted (user, 2026-10-06). To him this is a traveller in trouble who has walked out of the snow; only the hero is afraid of who might be behind him.

NARRATOR: You push in through the thorn. The ground goes soft underfoot, then softer. Somewhere behind you a branch cracks. You stop breathing until you are sure it was only bark splitting in the frost.

NARRATOR: Light between the trees. Lanterns, or water catching the moon? You can't tell any more.

NARRATOR: Your left hand won't stop shaking. You push it into your coat and hold it there, as if it belonged to someone else.

NARRATOR: Then the trees close in, and a bank of white mist lies across your path, low and still.

NARRATOR: Something moves in the mist ahead. You stop. So does it.

NARRATOR: A shape, man-high. A glint of brass at its belt.

*What do you do?*

▸ **Hold still.**
　NARRATOR: You make yourself very small. It doesn't help.
　MESSENGER: I can see you, you know.

▸ **Pick up a stone.**
　NARRATOR: Your hand finds a stone and closes on it.
　MESSENGER: Please don't. I've had a long day.

▸ **“Who's there?”**
　MESSENGER: Nobody worth throwing anything at.

NARRATOR: A young man steps out of the mist, breathing hard. Laurel in his hair, a satchel of letters at his hip.

MESSENGER: Oh. You're not a deer.

YOU: Who sent you?

MESSENGER: Sent me? The post, I suppose. Letters don't walk by themselves, more's the pity.

NARRATOR: He looks you over: the frost in your hair, the state of your boots. His smile thins into something more careful.

MESSENGER: You've come out of the snow? On foot?

YOU: …What of it?

MESSENGER: Nothing of it. Only that people who come that way don't usually arrive.

NARRATOR: He waits for you to go on, but you leave it there.

MESSENGER: Lost?

YOU: …Something like that.

MESSENGER: Ah, well. Best way to find the place. Nobody gets here on purpose.

NARRATOR: He holds out a flask worked with a pair of brass wings.

MESSENGER: Drink. It's still warm.

NARRATOR: You take it. Your fingers are so cold the brass almost burns.

NARRATOR: He notices. Before you can pull away, his hand closes over yours on the flask.

MESSENGER: Saints. You're freezing.

NARRATOR: His hand is hot from the road. He holds on until the flask stops shaking.

NARRATOR: Then he looks at you properly, for the first time. At your face, as if he were trying to place it.

MESSENGER: Have we met?

*What do you say?*

▸ **“No.”**
　MESSENGER: Hm… no, I suppose not. My mistake.

▸ **“I don't know.”**
　MESSENGER: You don't know? All right. Keep your mystery, then.

▸ **Take your hand back.**
　NARRATOR: He lets you. He doesn't seem to mind; he just takes his own hand back.

NARRATOR: You look back the way you came. Only trees, and the white beyond them.

MESSENGER: Expecting company?

YOU: No.

MESSENGER: Good. I've only the one flask.

MESSENGER: Right. You can't sleep out here. The cold comes down at night even this side of the snow. Not far on there's a village called the Lee.

MESSENGER: I've a letter for old Finn the charcoal-burner first. Keep to the way the stream runs, and I'll catch you up before you've gone a mile.

NARRATOR: He is gone between the trees before you can say you never agreed to anything. You are still holding his flask.

## 3. By the stream: `story.messenger.catch_up` (drag You onto the Messenger after the path; he stays on the table afterwards)

NARRATOR: Within the hour he catches you up, soaked to the knee and pleased with himself.

MESSENGER: There you are. You walk fast, for a man in that state.

NARRATOR: Ahead the trees thin. Beyond them smoke is rising, and under the smoke there are roofs.

MESSENGER: There. That's the Lee.

YOU: Why… is there no snow here?

MESSENGER: Snow? It hasn't come this far yet.

MESSENGER: Go further south and there are plenty of folk who've never seen it in their lives.

NARRATOR: You look down at the bare mud under your feet, and for a long moment you say nothing.

MESSENGER: Come on. A little further on, the grass is green.

MESSENGER: Only don't walk in on your own. Everyone's afraid of the Empire finding this place, and a strange face out of nowhere would frighten them. Stay with me.

NARRATOR: He sets off, then stops so suddenly that you nearly walk into his back. He turns, catches your arm to steady you, and leaves his hand there.

MESSENGER: Saints. I've been talking at you all this while and never asked your name.

*What do you say?*

▸ **Tell him your name.**
　YOU: {name}.
　MESSENGER: {name}… I like it. You're good-looking, too.
　MESSENGER: I'm Oisín.
　NARRATOR: His hand is still on your arm. Even through the sleeve you can feel the heat of it.

▸ **“You first.”**
　MESSENGER: All right, me first. Oisín.
　NARRATOR: As he says it he leans in, a hand's breadth from your face, and looks at you in earnest.
　MESSENGER: Odd. I still think I've seen you somewhere.
　YOU: {name}.
　MESSENGER: {name}… No, never heard it. So I haven't, then.
　NARRATOR: Only then does he straighten up.

▸ **Step back half a pace.**
　NARRATOR: You step back half a pace. He steps forward half a pace after you, his hand still on your arm.
　MESSENGER: Hm? What is it, are your legs going?
　YOU: …{name}.
　MESSENGER: {name}. I'm Oisín. …Your ears have gone red with the cold.
　NARRATOR: He puts up both hands and covers your ears.

NARRATOR: For a while you walk side by side along the stream.

MESSENGER: Who is it you're looking for, in the village?

YOU: …No one.

MESSENGER: Passing through, then? Heading south?

NARRATOR: You think about the south. You know nothing at all about the south.

YOU: I've nowhere I'm going.

NARRATOR: He doesn't speak at once. For a while there is only the sound of the stream.

MESSENGER: There's a house behind the mill that's stood empty two years. The roof lets the rain in. The door's sound, though.

MESSENGER: If you can put up with it, stay there for now. The rest can wait until you've slept.

NARRATOR: You follow him toward the smoke.

## 4. Card text

| ID | Title | Line |
|---|---|---|
| `card.hero` | You | On the run. |
| `card.loc.first_forest` | Blackthorn Wood | Wet, thorny, and dark enough to hide in. |
| `card.npc.messenger` | Messenger | Faster than the news. |
| `card.res.winter_seed` | Her Seed (老妇的种子) | They say it is hers. Every road in the country is closed for it. |
| `card.loc.stream_path` | Brookside (溪边小道) | Follow water and you come to people, sooner or later. |
| `card.loc.the_lee` | The Lee (背风地) | The snow has not reached it. Not yet. |

## 5. Onboarding goals

Stage `table_basics` "Know Your Table": `pan_table`, `zoom_table`, `drag_card` "Left-drag one card; right-drag a whole stack" (done by dragging one card), `walk_wood`. Stage `into_mist` "Into the Wood": `meet_messenger` "Talk to the man in the wood", `follow_stream` "Follow the brookside path", `hear_lee` "Hear about the Lee". Stage `shop_tools`: `focus_hero`, `change_time`, `open_recipes`, `open_relationships`.

---

## 写作说明

- **主角是普通人**：没有超能力，合成只是玩法。他的来历和罪名写在 `world-bible.md` §7，开场不说。
- **矛盾只有一条**：帝国借白冬起家、靠白冬统治。序幕：自由城镇 → 白冬年年蔓延 → 一个人带着运粮车和长矛跟着雪走，饥饿的城镇为面包开门，名字被写上他的地图 → 他称帝，白冬从此为他的家族效力 → 地图边缘有人在逃，他找到了对抗白冬的线索。文风是史诗西幻（绝对魔权、哈迪斯、指环王序章），不是古风。
- **林子和背风地都是普通的**：林子只是又湿又密、够黑能藏人；背风地在帝国地图的边缘，是城镇被冬天吞掉后逃难的人落脚的村子，太远了，帝国懒得管。
- **危险具体**：追兵在雾里丢了踪迹，天亮会再找到；狗叫声越来越近。信使拿主角的围巾把狗引开，一个钟头后湿着膝盖回来，把还带着他体温的围巾还给主角。
- **信使的张力**：握手暖壶、认真看主角的脸问“我们见过吗？”、要一件贴身的东西、围巾上的体温。都是具体动作，不说破。
- **两条规矩都和村子有关**：没人问你从哪儿来；别一个人进村，那里的人见过兵，在立石等他。

## 实现状态

已接入游戏，作为临时内容，一直可玩到抵达立石。下一段：背风地、待客之道、Bríd 的空作坊，以及主角第一次造物。

## 备用场景（暂不接入）

v0.6–v0.7 写过、现已不用的两场，保留供以后取用。

### The treeline (Lucan): `story.opening.treeline` (starts by itself; no stacking)

NARRATOR: Behind you the lamps stop, one by one. One keeps coming. It reaches the first tree, and stops too.

LUCAN: One more step and you're off the map.

YOU: There's nothing on the map here.

LUCAN: No. That's what bothers them.

NARRATOR: He lifts the lamp. The light reaches the mist and goes no further.

LUCAN: You filed it off.

YOU: It was too tight.

LUCAN: It was meant to be.

NARRATOR: The wick hisses. The flame shrinks to the size of a seed.

LUCAN: Come back. I'll say it cracked. Iron cracks in the cold. I'll say you were on your way back to Kingsford when I found you.

▸ **"You've said things for me before."**
　LUCAN: I have. I said them well.

▸ **"Then you shouldn't have followed so close."**
　LUCAN: Anyone else would have followed closer.

▸ *[Step back into the mist.]*
　NARRATOR: The mist takes your ankles. He watches it. He doesn't move.

LUCAN: …I'll wait by the river until dawn.

LUCAN: After dawn, it won't be me.

NARRATOR: You turn. Mist at your knees, at your waist. Behind you the lamp grows small, and then it closes, like an eye.

NARRATOR: Ahead, the mist draws aside. Not far. Just wide enough for one.

> Cards appear: **You**, **Blackthorn Wood**.
> Hint: **Drag yourself onto Blackthorn Wood.**


### The snare: `story.woodward.first_meeting` (place You beside the Woodward)

NARRATOR: The snare makes almost no sound. By the time you notice, your left ankle is caught in waxed cord and hung from a bent blackthorn.

NARRATOR: Someone comes out of the mist. First a staff, then boots, then the man: tall, a dead hare over one shoulder. He looks at you much the way he looks at the hare.

WOODWARD: That was set for hares.

YOU: I gathered.

WOODWARD: Hares don't usually fight it this hard.

NARRATOR: He crouches. The knife comes out, a good Easterling blade, too good for a man who snares hares. You go still. He cuts the cord.

WOODWARD: Don't move. It's bitten in.

NARRATOR: He cups your heel in one palm and runs his thumb along the welt, feeling for the bone. His hand is steady, and warm. Warmer than anything you've touched in two days.

WOODWARD: You'll walk. Not fast.

NARRATOR: He holds out a hand. You take it. He pulls you up, and doesn't let go at once. His thumb has found the pale band on your finger.

NARRATOR: He looks at it a moment longer than he needs to.

WOODWARD: Someone waiting for you?

▸ **"No."**
　WOODWARD: Mm.

▸ **"Not any more."**
　NARRATOR: He nods, as if that were an answer to something else as well.

▸ **"It wasn't that kind of ring."**
　NARRATOR: He looks at you. Then at the mist behind you, the way you came.
　WOODWARD: No. I don't suppose it was.

NARRATOR: He lets go.

YOU: What's your name?

WOODWARD: Not in the wood.

YOU: Then what do I call you?

WOODWARD: Nothing, for now. You'll manage.

WOODWARD: How did you get past the edge?

YOU: The mist opened.

NARRATOR: For the first time, he really looks at you.

WOODWARD: It doesn't do that.

YOU: It did.

NARRATOR: A long silence. The mist moves between you, as if something were leaning in to listen.

NARRATOR: He shifts the hare to his other shoulder.

WOODWARD: Then the Thorn's let you in, and that's the Thorn's business.

WOODWARD: North of here there's a badger track. At the end of it, the Lee.

YOU: The Lee?

WOODWARD: Out of the wind. You'll see.

YOU: You're not taking me?

WOODWARD: I've seven snares left to check.

NARRATOR: A pause.

WOODWARD: Wait where the track meets the stones. Don't touch anything. Especially the stones.

YOU: And if I don't wait?

WOODWARD: Then you're the second thing today that walked into a snare by itself.

WOODWARD: …I'll come and find you.

NARRATOR: He goes without looking back. You find you've been watching his back until the mist folds it away.

> The Woodward leaves; **Badger Track** appears where he stood.
> Hint: **Drag yourself onto Badger Track.**
> Walking it gives **The Stones**. End of segment.


## 历史

- v1.5 → v1.6：用户定下世界主线：帝国的开创者借白冬把自由城镇一座座写上地图，建立帝国；白冬仍在蔓延、为帝国效力；主角逃到帝国势力边缘，因为找到了对抗白冬的方法的线索而被通缉。文风为史诗西幻。序幕重写。
- v1.4 → v1.5：按用户意见，林子和村子改为普通的（不再强调帝国没碰过的地方），序幕不牵扯其他国家，只写白冬和帝国借白冬对百姓的压迫；信使那段去掉雾的神秘感，改为追兵天亮会找到踪迹、他用主角的围巾引开猎狗；规矩改为“没人问你从哪儿来”“别一个人进村”。主角来历改为：白冬时被帝国用一袋粮换走的孩子，长成骑士后拒绝烧村、砍倒队长出逃（设定集 §7，开场不说）。
- v1.3 → v1.4：按用户要求把白冬放回序幕，但改为直接服务主线：白冬让帝国借运粮吞并西方、画完地图；只有那片林子整个白冬都是绿的、没画进地图，走进去的饥民就是背风地的来历。序幕五页。
- v1.2 → v1.3：去掉戒指（为一个奇特物品硬造的设定）；主角改为没有超能力的普通人，合成只是玩法；王室统一改回帝国；序幕改写为“帝国画地图、唯独这片林子没画进去、帝国要活捉他”；信使认戒指的一段改为“我们见过吗？”。主角的罪名（他是唯一认得进林之路的人，带帝国远征队到林边时反水）写进设定集，开场不说。
- v1.1 → v1.2：用户否决 v1.1 的写法和设定“很 AI”：故意用拗口的词、拼凑与主线无关的设定（好心人、冷铁、白冬、铁之和平、《土地之书》等）全部删去；追捕只针对主角一人；序幕缩为四页，只讲造物、戒指、他、追捕、林子；主角的逃亡并入对话框作为旁白；信使的规矩减为两条；所有正文左对齐，序幕去掉标题和边框。
- v1.0 → v1.1：序幕重写得更直白、更有魔法感（多一页“好心人”，冷铁戒指压制魔法）；主角四页加入魔法的身体感受；序幕整体居中；取名移到序幕之后。
- v0.9 → v1.0：序幕改为全屏呈现，配六张插画；獾道接上通用地点探索，走完到达立石。
- v0.8 → v0.9：开头加入六页有仪式感的序幕“铁之和平”，讲世界的历史和主要矛盾（参考《绝对魔权》的开场），最后一句交给正在奔逃的主角；开场文字页支持逐页标题。
- v0.7 → v0.8：去掉执法官 Lucan，开场只写主角逃亡的紧张；林边对话改为与信使相遇，背景通过他的话透出；信使登场前不显示立绘。
- v0.6 → v0.7：林子里先遇到的人从守林人改为信使（新手导师），守林人那场戏转为备用；接入游戏。
- v0.5 → v0.6：埋下外部世界的地名（Blackwater、Book of the Land、Kingsford、Easterling）。
- v0.4 → v0.5：用词对齐 `world-bible.md`（maker、手变冷的代价、the Thorn）。
- v0.3：核心词 leaf 被否决，像生造的名词，为怪而怪。v0.4 直接去掉，不再造替代词；方向改为“巫师 + 合成”，卡牌只作为玩法的表现形式。
- v0.2：中文译稿用了古风词，已撤下；改为先完成英文。
- v0.1：主角“听名字”的能力和玩法无关，名字像硬拼出来的，已被否决。

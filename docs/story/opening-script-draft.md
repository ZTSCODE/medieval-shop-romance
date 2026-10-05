# Opening Script Draft v1.6

Status: **in the game** (2026-10-03) as temporary content, awaiting user review. English is the source; the Chinese sits beside it in `tools/content/build_opening.py`, which writes `data/content.json` and `localization/game.csv` (glossary: `opening-zh-glossary.md`). The script below is regenerated from that data, so edit the generator, not this file. Setting: `world-bible.md`. Method: `narrative-methodology.md`. Implementation: `docs/knowledge/opening-story-runtime.md`.

User direction (2026-10-03): first a ceremonial chronicle with a sense of history that sets out the world's central conflict (after Absolum's intro); then the hero's own pages have **only the hero**: the tension and suspicion of the flight, no exposition. The person the hero talks to is **the Messenger**, the player's mentor; the hero's situation and the world come out through that conversation. No Warden.

## Flow

| # | Beat | Player does | Cards after |
|---|---|---|---|
| 1 | Chronicle, five pages, full screen | Reads (time paused) | (You and the wood wait under the dark) |
| 2 | Name the hero | Types a name | |
| 3 | At the edge: the flight, then a shape in the mist is the Messenger | Reads, two choices | **You**, **Blackthorn Wood** |
| 4 | Tutorial: walk the wood | Drag You onto Blackthorn Wood (≈8 s) | You, **Messenger**, **Sloes** |
| 5 | The Messenger's two rules | Drag You onto the Messenger | You, Sloes, **Badger Track** (he runs ahead) |
| 6 | Follow the track | Drag You onto Badger Track (≈6 s) | You, Sloes, **The Stones** |

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
> Now, at the ragged edge of that map, a man runs for his life, with forty riders and their dogs behind him.
> He has found a clue to the one thing the Empire cannot allow: a way to stand against the White Winter.

After the last page the game asks for the player's name (no cancel).

## 2. At the edge: `story.messenger.edge` (starts by itself after naming; the Messenger's portrait stays hidden until he steps out)

NARRATOR: Your lungs burn. The ground goes soft underfoot, then softer. Somewhere behind you a dog barks once, and stops.

NARRATOR: Lanterns between the trees. Or water catching the moon. You can't tell any more.

NARRATOR: Your left hand won't stop shaking. You push it into your coat and hold it there, as if it belonged to someone else.

NARRATOR: Then the trees close in, and a bank of white mist lies across your path, low and still.

NARRATOR: Something moves in the mist ahead. You stop. So does it.

NARRATOR: A shape, man-high. A glint of brass at its belt.

*What do you do?*

▸ **[Hold still.]**
　NARRATOR: You make yourself very small. It doesn't help.
　MESSENGER: I can see you, you know.

▸ **[Pick up a stone.]**
　NARRATOR: Your hand closes on a stone. Cold, and too small to matter.
　MESSENGER: Please don't. I've had a long day.

▸ **“Who's there?”**
　MESSENGER: Nobody worth throwing anything at.

NARRATOR: A young man steps out of the mist, breathing hard. Laurel in his hair, a satchel of letters at his hip.

MESSENGER: Oh. You're not a deer.

YOU: Who sent you?

MESSENGER: The post sent me. Nobody sends me after people. I'm not fast enough to be frightening.

NARRATOR: He looks past you, back the way you came. His smile thins.

MESSENGER: Someone sent them, though.

YOU: Them?

MESSENGER: The lamps. Down by the river. They lost your trail when the mist came up. They'll find it again by first light.

NARRATOR: You don't turn round. You don't trust yourself to.

MESSENGER: You've been running.

YOU: So have you.

MESSENGER: I'm paid to. You look like stopping would cost you.

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
　MESSENGER: No. I'd remember.

▸ **“I don't know.”**
　MESSENGER: Then you've got one of those faces.

▸ **[Take your hand back.]**
　NARRATOR: He lets you. He doesn't look offended. He looks like a man filing something away for later.

NARRATOR: Far behind you, the dogs again. Closer than before.

MESSENGER: Right. Here's what we'll do.

MESSENGER: There's a stream past those trees. Walk in it, not beside it, and keep going until the wood thins.

YOU: And you?

MESSENGER: Give me something you've been wearing.

NARRATOR: You hand him your scarf. He winds it round his own neck without a word.

MESSENGER: I'll take the dogs a mile the other way, then catch you up. Go.

> Cards appear: **You**, **Blackthorn Wood**. Hint: **Drag yourself onto Blackthorn Wood.**

## 3. In the wood: `story.messenger.thorn_rules` (drag You onto the Messenger)

NARRATOR: An hour later he catches you up, soaked to the knee and pleased with himself.

MESSENGER: They went the wrong way. Dogs love a scarf.

NARRATOR: He gives you back your scarf. It is still warm from his neck.

MESSENGER: So. Two things, since nobody's told you.

MESSENGER: One. In the Lee, nobody asks where you came from. Don't ask them either.

MESSENGER: Two. Don't walk into the village alone. They've had soldiers there before. Wait at the stones by the track, and I'll bring you in.

NARRATOR: He crouches by a blackthorn, picks a sloe, frowns at it, and drops it into your palm.

MESSENGER: Keep those. Bitter now. After the first frost, they're worth something.

YOU: What is the Lee?

MESSENGER: A place people stopped running, when the winter took their towns. It's too far out for the Empire to bother with. Which, by the look of you, is the right place.

MESSENGER: North of here there's a badger track. Follow it to the stones.

YOU: You're not coming?

MESSENGER: I'm faster. I'll run ahead and tell the Lee someone's coming.

MESSENGER: They'll feed you before they ask you anything. That's the custom.

NARRATOR: He's already walking backwards, grinning.

MESSENGER: Don't look so worried. I'll be there when you arrive. I always am.

NARRATOR: Then he turns and runs into the trees.

NARRATOR: You wind the scarf back round your neck. It still holds the warmth of him.

> The Messenger leaves; **Badger Track** appears where he stood. Walking it (≈6 s) turns it into **The Stones**, where he said to wait. End of segment; next is the Lee.

## 4. Card text

| ID | Title | Line |
|---|---|---|
| `card.hero` | You | On the run. |
| `card.loc.first_forest` | Blackthorn Wood | Wet, thorny, and dark enough to hide in. |
| `card.npc.messenger` | Messenger | Faster than the news. |
| `card.res.sloes` | Sloes | Bitter until the frost gets to them. |
| `card.loc.badger_track` | Badger Track | The badgers were here first, and would like that remembered. |
| `card.loc.the_stones` | The Stones | Wait here for him. |

## 5. Onboarding goals

Stage `into_mist` "Into the Mist": `walk_wood` "Walk into Blackthorn Wood" (`opening_explored`); `meet_messenger` "Hear the Messenger out" (`story_completed:story.messenger.thorn_rules`).

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

"""Rewrites the four story sections of docs/story/opening-script-draft.md from data/content.json and game.csv."""
import csv
import json

content = json.load(open('data/content.json', encoding='utf-8'))
en = {r[0]: r[2] for r in csv.reader(open('localization/game.csv', encoding='utf-8', newline='')) if len(r) >= 3}
WHO = {'narrator': 'NARRATOR', 'hero': 'YOU', 'npc': 'MESSENGER'}


def story(story_id):
    out = ''
    for line in content['stories'][story_id]['lines']:
        if line.get('choices'):
            out += '*%s*\n\n' % en[line['text_key']]
            for option in line['choices']:
                out += '▸ **%s**\n' % en[option['text_key']]
                for reply in option['lines']:
                    out += '　%s: %s\n' % (WHO[reply['speaker']], en[reply['text_key']])
                out += '\n'
            continue
        out += '%s: %s\n\n' % (WHO[line['speaker']], en[line['text_key']])
    return out


p = 'docs/story/opening-script-draft.md'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')


def body(heading_start, next_marker, text):
    global s
    i = s.index(heading_start)
    i = s.index('\n', i) + 1
    j = s.index(next_marker, i)
    s = s[:i] + '\n' + text + s[j:]


body('## 1a. Where the snow gives out', '*(Blackthorn Wood slides onto the table', story('story.hero.thaw_edge'))
body('## 1b. The wood:', '*(The goals panel opens', story('story.hero.wood_doubt'))
body('## 2. Inside the wood:', '## 3. By the stream:',
     'The Messenger does not know the hero is hunted (user, 2026-10-06). To him this is a traveller in trouble who has walked out of the snow; only the hero is afraid of who might be behind him.\n\n'
     + story('story.messenger.edge'))
body('## 3. By the stream:', '## 4. Card text', story('story.messenger.catch_up'))
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('ok')

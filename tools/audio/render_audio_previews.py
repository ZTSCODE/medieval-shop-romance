"""Offline audition mixes from the exact catalog. Not a capture of engine output.
Requires Python 3, NumPy and ffmpeg. Run from project root.
"""
from pathlib import Path
import json, subprocess, numpy as np, csv
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/audio/previews';OUT.mkdir(parents=True,exist_ok=True)
CAT=json.loads((ROOT/'assets/audio/audio_catalog.json').read_text())['events'];MAP=json.loads((ROOT/'assets/audio/narrative_cues.json').read_text())['lines'];RATE=48000
cache={};indices={}
def samples(path):
 if path not in cache:
  data=subprocess.check_output(['ffmpeg','-v','error','-i',str(ROOT/path.removeprefix('res://')),'-ar',str(RATE),'-ac','2','-f','f32le','-']);cache[path]=np.frombuffer(data,dtype=np.float32).reshape(-1,2).copy()
 return cache[path]
def voice(e,seconds=None,pan=0,offset=0):
 spec=CAT[e];index=indices.get(e,0);indices[e]=index+1;a=samples(spec['files'][index%len(spec['files'])]).copy()
 if seconds is not None:a=np.tile(a,(int(seconds*RATE/len(a))+1,1))[:int(seconds*RATE)]
 gain=10**((spec['gain_db']+offset)/20)*.8*(.7 if spec['bus']=='MusicMix' else .8)
 if spec['bus']=='MusicMix':gain*=.70
 a*=gain
 # Godot AudioEffectPanner: linear attenuation of opposite channel.
 if pan<0:a[:,1]*=1+pan
 if pan>0:a[:,0]*=1-pan
 return a
rows=[]
def put(dst,e,t,seconds=None,pan=0,offset=0,fade=0,quote='',key='',reason=''):
 a=voice(e,seconds,pan,offset);n=int(fade*RATE)
 if n and len(a)>2*n:a[:n]*=np.linspace(0,1,n)[:,None];a[-n:]*=np.linspace(1,0,n)[:,None]
 i=int(t*RATE);size=min(len(a),len(dst)-i);dst[i:i+size]+=a[:size]
 rows.append({'time_seconds':t,'duration_seconds':round(size/RATE,3),'event':e,'text_key':key,'quote_zh':quote,'pan':pan,'catalog_gain_db':CAT[e]['gain_db'],'offset_db':offset,'purpose':reason})
def save(stem,a):
 peak=float(np.max(abs(a)));rms=float(np.sqrt(np.mean(a*a)));# Preserve actual configured relative levels; no artificial normalization.
 subprocess.run(['ffmpeg','-y','-v','error','-f','f32le','-ar',str(RATE),'-ac','2','-i','pipe:0','-c:a','libmp3lame','-q:a','2',str(OUT/(stem+'.mp3'))],input=a.astype(np.float32).tobytes(),check=True)
 return {'filename':stem+'.mp3','seconds':len(a)/RATE,'peak_dbfs':20*np.log10(max(peak,1e-12)),'rms_dbfs':20*np.log10(max(rms,1e-12)),'kind':'offline_catalog_audition_not_game_capture'}
a=np.zeros((76*RATE,2));put(a,'ambience.snowline',0,15,fade=2,reason='User snowline context: exposed gusts retreat as trees shelter the player');put(a,'ambience.cold_wood',12,64,fade=3,reason='Thawed thornwood; no added bird/cricket chorus')
def beat(key,at):
 entry=MAP[key]
 for c in entry['cues']:
  # Compressed reading montage: exact authored phrases keep the same cue identity.
  put(a,c['event'],at+c.get('delay_seconds',0),pan=c.get('pan',0),offset=c.get('gain_offset_db',0),quote=entry['quote_zh'],key=key,reason='Exact configured narrative phrase: '+c['phrase'])
beat('DLG_MESSENGER_EDGE_01',1.2)
# Separate the dog phrase from the foot-ground phrase in this montage.
# Rebuild first 8 seconds with exact phrase placement instead of simultaneous line cue start.
a[:8*RATE]=0
rows=[r for r in rows if not r['text_key']=='DLG_MESSENGER_EDGE_01']
# Retain wind at the same phase across the reset section.
a[:8*RATE]=voice('ambience.snowline',15)[:8*RATE];a[:2*RATE]*=np.linspace(0,1,2*RATE)[:,None]
entry=MAP['DLG_MESSENGER_EDGE_01']
for c,t in zip(entry['cues'],[1.2,4.1]):put(a,c['event'],t,pan=c.get('pan',0),quote=entry['quote_zh'],key='DLG_MESSENGER_EDGE_01',reason=c['phrase'])
for k,t in [('DLG_MESSENGER_EDGE_03',9),('DLG_MESSENGER_EDGE_04',13),('DLG_MESSENGER_EDGE_07',20),('DLG_MESSENGER_EDGE_19',25.5),('DLG_MESSENGER_EDGE_21',32),('DLG_MESSENGER_EDGE_27',37.5),('DLG_MESSENGER_EDGE_32',41),('DLG_MESSENGER_RULES_01',53),('DLG_MESSENGER_RULES_03',57),('DLG_MESSENGER_RULES_07',61.5),('DLG_MESSENGER_RULES_17',66.5),('DLG_MESSENGER_RULES_18',72)]:beat(k,t)
put(a,'movement.stream_escape',44,8,fade=.2,key='opening.explore',quote='实际叠卡探索黑刺李林，走入溪水避开追踪',reason='Actual player action, never EDGE29 instruction')
put(a,'music.story',57,19,fade=3,key='DLG_MESSENGER_RULES_03',reason='Restrained warmth only after dogs were diverted; actual -24dB trim')
a[-RATE:]*=np.linspace(1,0,RATE)[:,None]
reports=[save('narrative_snowline_to_thornwood_76s',a)]
with (OUT/'narrative_preview_timeline.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(sorted(rows,key=lambda r:r['time_seconds']))
(OUT/'narrative_preview_timeline.json').write_text(json.dumps(sorted(rows,key=lambda r:r['time_seconds']),ensure_ascii=False,indent=2)+'\n')
rows=[];indices={};order=['ui.hover','ui.press','ui.toggle','ui.slider','book.open','book.page','book.close','card.select','card.pick','card.split','card.drop','card.stack','card.unfold','card.fly','card.land','card.reject','card.cancel','goal.check','goal.complete','ui.confirm'];a=np.zeros((40*RATE,2))
for i,e in enumerate(order):put(a,e,.5+i*1.9,reason='UI/card catalog sampler')
reports.append(save('ui_card_book_sampler_40s',a));(OUT/'preview_validation.json').write_text(json.dumps(reports,indent=2)+'\n')
(OUT/'README.txt').write_text('试听说明\n这两段是按游戏当前事件目录与音量配置离线合成的试听，不是云端游戏录音。云端 Godot 实机只有 Dummy 音频驱动；需要在你的设备上听感确认。\n\n76秒叙事试听是压缩的分镜蒙太奇，不代表所有文字应在76秒内读完。0–12秒雪线边缘强风、脚步、远犬；12–24秒入林收风、停步、来人；24–35秒水壶近身接触；35–44秒同一犬声更近、围巾交接；44–52秒只有实际探索时才踏入溪水；52–76秒归来、危险解除后的微弱暖意、浆果与离去。原始开场影片音轨未修改。\n完整时刻、原句、事件与声像见同目录时间线。所有音量保持当前目录相对关系，未另做响度归一化。\n',encoding='utf-8')
print(json.dumps(reports,indent=2))

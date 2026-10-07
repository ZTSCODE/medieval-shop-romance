"""Assemble and audit the chronicle Blender blocking, preserving individual shots."""
from pathlib import Path
import json,subprocess,html
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'outputs/chronicle-full-animatic-20261003'
shots=json.loads((OUT/'shots.json').read_text(encoding='utf-8'))
shots=[dict(id='01',frames=22,title='地图落印 → 驻兵',page='page1',source='chronicle-map-animatic-20261003',start=39),dict(id='02',frames=48,title='士兵入城',page='page1',source='chronicle-soldiers-animatic-20261003',start=1)]+shots
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
def run(args):subprocess.run(args,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
offset=0
for s in shots:
 folder=ROOT/'outputs'/s['source'] if 'source' in s else OUT/('shot'+s['id'])
 frames=folder/'frames';start=s.get('start',1);s['start_seconds']=offset/24;s['duration_seconds']=s['frames']/24;offset+=s['frames']
 s['frame_paths']=[str(frames/f'frame_{i:04d}.png') for i in [start,start+s['frames']//2,start+s['frames']-1]]
 for p in s['frame_paths']:assert Path(p).is_file(),p
 run(['ffmpeg','-y','-loglevel','error','-framerate','24','-start_number',str(start),'-i',str(frames/'frame_%04d.png'),'-frames:v',str(s['frames']),'-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/('shot'+s['id']+'.mp4'))])
 s['blend']=str(folder/(('map-shot01' if s['id']=='01' else 'soldiers-shot02' if s['id']=='02' else 'shot'+s['id'])+'.blend'))
 assert Path(s['blend']).is_file()
for batch in range(4):
 entries=shots[batch*4:batch*4+4];im=Image.new('RGB',(960,len(entries)*210),(22,27,30));d=ImageDraw.Draw(im)
 for row,s in enumerate(entries):
  d.text((8,row*210+4),f"{s['id']}  {s['title']} / {s['duration_seconds']:.2f}s",font=font,fill=(230,230,225))
  for col,p in enumerate(s['frame_paths']):im.paste(Image.open(p).resize((320,180)),(col*320,row*210+30))
 im.save(OUT/f'contact-{batch+1}.jpg',quality=95)
(OUT/'concat.txt').write_text('\n'.join("file 'shot"+s['id']+".mp4'" for s in shots),encoding='utf-8')
run(['ffmpeg','-y','-loglevel','error','-f','concat','-safe','0','-i',str(OUT/'concat.txt'),'-c','copy','-movflags','+faststart',str(OUT/'chronicle-full.mp4')])
run(['ffmpeg','-v','error','-i',str(OUT/'chronicle-full.mp4'),'-f','null','-'])
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(OUT/'chronicle-full.mp4')]))
v=probe['streams'][0];assert int(v['nb_frames'])==offset and v['width']==640 and v['height']==360 and v['r_frame_rate']=='24/1'
assert max(s['frames'] for s in shots)<=72
report=dict(total_frames=offset,duration_seconds=offset/24,resolution=[640,360],fps=24,full_decode='passed',max_shot_seconds=max(s['frames'] for s in shots)/24,audio='none - motion blocking only',reference_match='not verified; reference player inaccessible',art_approval=False)
(OUT/'qc.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'edit-manifest.json').write_text(json.dumps(shots,ensure_ascii=False,indent=2),encoding='utf-8')
cards=''.join(f'<button onclick="seek({s["start_seconds"]})">{s["id"]} · {html.escape(s["title"])} <small>{s["duration_seconds"]:.2f}s</small></button>' for s in shots)
blends=''.join(f'<li><a href="{Path(s["blend"]).as_uri()}">{s["id"]} {html.escape(s["title"])} · Blender</a> · <a href="shot{s["id"]}.mp4">单镜视频</a></li>' for s in shots)
page='''<!doctype html><html lang="zh"><meta charset="utf-8"><title>开场编年史 · 完整动态分镜</title><style>body{background:#111b22;color:#e7ddd0;font:17px system-ui;margin:0 auto;max-width:1120px;padding:28px}h1{font-size:27px}p{line-height:1.7;color:#b7c2c8}video{width:100%;max-height:65vh;background:#05080a}button{background:#30414c;color:#f7e7cf;border:1px solid #51616d;border-radius:4px;padding:11px;margin:4px;cursor:pointer}small{opacity:.65}a{color:#e0bd7f}nav{display:flex;flex-wrap:wrap}img{max-width:100%}.note{padding:14px;background:#302b24}#now{color:#dfb77c}</style><h1>开场编年史 · 14 镜动作草稿</h1><p>640 × 360 · 24 fps · 每镜 ≤ 2.5 秒 · 无声动态分镜。人偶、布片及雾层均为动作占位；不是最终动画美术。</p><p class="note">主要参考：用户指定的 Absolum Reveal Trailer。参考播放器尚未成功读取，因此本版尚未通过参考风格对照，也未提交 MiniMax。先检查叙事、镜头和动作。</p><video id="v" controls preload="metadata" src="chronicle-full.mp4"></video><p id="now"></p><nav><button onclick="v.paused?v.play():v.pause()">播放 / 暂停</button><button onclick="step(-1)">前一帧</button><button onclick="step(1)">后一帧</button><button onclick="v.playbackRate=.5">半速</button><button onclick="v.playbackRate=1">原速</button><button onclick="seek(0)">从头</button></nav><h2>逐镜跳转</h2>CARDS<h2>源文件</h2><ul>BLENDS</ul><h2>首 / 中 / 尾帧</h2>CONTACTS<script>const shots=SHOTS,v=document.querySelector('#v');function seek(t){v.currentTime=t;v.pause()}function step(n){v.pause();v.currentTime=Math.max(0,Math.min(v.duration||100,v.currentTime+n/24))}v.addEventListener('timeupdate',()=>{const s=shots.findLast(s=>v.currentTime>=s.start_seconds)||shots[0];document.querySelector('#now').textContent=s.id+' · '+s.title+' — '+v.currentTime.toFixed(2)+' 秒'});</script></html>'''
page=page.replace('CARDS',cards).replace('BLENDS',blends).replace('CONTACTS',''.join(f'<img src="contact-{i}.jpg">' for i in range(1,5))).replace('SHOTS',json.dumps(shots,ensure_ascii=False))
(OUT/'index.html').write_text(page,encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))

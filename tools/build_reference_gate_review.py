"""Assemble an explicit unapproved component review without changing game skins."""
from pathlib import Path
import json
import html
import reference_component_gate as gate

root=gate.ROOT
out=gate.OUT
parts=json.loads((out/'components.json').read_text(encoding='utf8'))
candidate_root=root/'assets/art/ui/reference_parts_20260922'
mapping={
 'hud_axis':('hud/axis-paper-candidate-v2.png','纸形仍偏窄，左下出现原图没有的大块灰色磨损。'),
 'hud_recipe':('hud/recipe-button-candidate-v2.png','碗形和勺的角度仍不同；薄亮边较均匀。'),
 'hud_relationship':('hud/relationship-button-candidate-v2.png','人物符号更小、更靠下；与原图位置、比例均不符。'),
 'hud_portrait':('hud/avatar-frame-candidate-v2.png','下部浅纸的上缘比原图高，顶段笔触更粗，边缘颜色偏亮。'),
 'relation_outer':('journal/journal-outer-candidate-v1.png','外边层次和角点位置仍不同，边沿偏厚。'),
 'relation_title':('journal/journal-title-candidate-v3.png','题签主体比例较原图宽，叠纸上沿与角点不同。'),
 'relation_selected':('journal/journal-selected-row-candidate-v2.png','左右纸边偏亮，红褐色与纹理分布仍不同。'),
 'relation_normal':('journal/journal-normal-row-candidate-v1.png','灰绿颜色近似，但内部笔触、外边角轮廓不一致。'),
 'relation_detail':('journal/journal-detail-candidate-v1.png','边缘偏亮且较均匀，原纸面笔触方向不同；分隔与花枝需另件对照。'),
 'relation_close':('journal/journal-close-candidate-v2.png','轮廓宽高及边损位置不同，浅纸色尚未匹配。'),
 'recipe_outer':('journal/recipe-outer-candidate-v1.png','背景偏暖亮，植物印花位置和纸面笔触不一致。'),
}
rows=[]
for key, meta in parts.items():
    if key in mapping:
        file, reason=mapping[key]
        result=gate.compare(key,candidate_root/file,meta['exclusions'])
        result['edge_review']='fail'
        result['hierarchy_review']='blocked_by_components'
        result['manual_notes']=reason
        (out/'comparisons'/(Path(result['comparison']).stem+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
        meta.update(candidate=str((candidate_root/file).relative_to(root)),status='rejected',review=reason,
                    report='comparisons/'+Path(result['comparison']).with_suffix('.json').name)
        rows.append(f'<section><h2>{html.escape(key)} <strong>未通过</strong></h2><p>{html.escape(reason)}</p><p>平均误差 {result["mae"]:.2f}/255 · 95分位 {result["p95_error"]:.0f}/255 · 局部SSIM {result["ssim_8x8"]:.3f}（要求≥0.90）</p><a href="comparisons/{result["comparison"]}"><img src="comparisons/{result["comparison"]}"></a><p>左：原图；中：候选；右：差异，蓝色为预登记排除区。未进行颜色校正或变形对齐。</p></section>')
    else:
        meta.update(status='not_reviewed',review='尚无独立候选或尚未分层验证，不视为通过。')
        rows.append(f'<section><h2>{html.escape(key)} <strong>待制作/待核对</strong></h2><img class="reference" src="reference-crops/{key}.png"><p>无门禁通过记录。</p></section>')
all_reports={'status':'not_approved','production_changed':False,'passed':0,'total':len(parts),'parts':parts}
(out/'gate-summary.json').write_text(json.dumps(all_reports,ensure_ascii=False,indent=2),encoding='utf8')
(out/'components.json').write_text(json.dumps(parts,ensure_ascii=False,indent=2),encoding='utf8')
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>原图组件严格门禁 · 尚未通过</title><style>body{margin:0;background:#181715;color:#e9e3d6;font:16px/1.6 system-ui}main{max-width:1500px;margin:auto;padding:30px}h1{font-size:27px}h2{font-size:20px}strong{color:#efaa8f;margin-left:15px}section{padding:24px 0;border-top:1px solid #484138}img{display:block;max-width:100%;height:auto}.reference{max-height:400px}p{color:#b9b3aa}.notice{padding:20px;background:#342722;border:1px solid #8a5b43}a{color:#d5c5a4}</style><main><h1>原图组件严格门禁 · 0项放行</h1><div class="notice">本页是候选审查，不是新版实机或完成证明。当前正式游戏皮肤未替换。功能通过不抵扣美术差异。所有生成、透明度检查和数值预筛均不自动授予通过。</div><p>原图基准：02-table / 04-relations / 05-recipes。原分辨率1672×941。已拆20项；动态文字、原有角色插画和真实内容的排除区在评分前登记。静态纸边、图标、纸色不排除。原图并非分层源文件，部分被遮挡纸面不能作为可验证的真值，仍需单独层级核对。</p><p>生成图与原图的笔触、轮廓仍有差异。本轮没有降低门槛、没有靠功能测试放行，也没有把这些候选覆盖到游戏中。层级坐标图见 <a href="layers.json">layers.json</a>；完整状态见 <a href="gate-summary.json">gate-summary.json</a>。</p>'''+''.join(rows)+'</main></html>'
(out/'index.html').write_text(page,encoding='utf8')
print('Review assembled: 0 approved, production skin unchanged')

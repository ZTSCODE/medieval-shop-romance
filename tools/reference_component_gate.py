"""Produce source crops and strict, non-color-corrected visual comparisons."""
from pathlib import Path
import json
import argparse
import hashlib
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'outputs/ui-reference-gate-20260922'
REFERENCES = ROOT / 'outputs/ui-smoke-brown-suite-20260919'
PARTS = {
    'hud_axis': ('02-table.png', (1535, 107, 1637, 392)),
    'hud_day': ('02-table.png', (1519, 59, 1648, 115)),
    'hud_recipe': ('02-table.png', (1538, 409, 1639, 512)),
    'hud_relationship': ('02-table.png', (1539, 539, 1639, 630)),
    'hud_portrait': ('02-table.png', (1532, 645, 1644, 835)),
    'relation_outer': ('04-relations.png', (286, 191, 1398, 764)),
    'relation_title': ('04-relations.png', (727, 155, 949, 215)),
    'relation_selected': ('04-relations.png', (342, 254, 604, 390)),
    'relation_normal': ('04-relations.png', (342, 400, 604, 539)),
    'relation_portrait': ('04-relations.png', (629, 253, 949, 718)),
    'relation_detail': ('04-relations.png', (939, 253, 1364, 737)),
    'relation_close': ('04-relations.png', (1236, 690, 1339, 745)),
    'recipe_outer': ('05-recipes.png', (274, 207, 1409, 778)),
    'recipe_title': ('05-recipes.png', (727, 169, 949, 231)),
    'recipe_heading': ('05-recipes.png', (303, 253, 564, 307)),
    'recipe_selected': ('05-recipes.png', (298, 319, 576, 430)),
    'recipe_normal': ('05-recipes.png', (298, 438, 576, 553)),
    'recipe_close': ('05-recipes.png', (1225, 722, 1342, 778)),
    'recipe_divider': ('05-recipes.png', (578, 249, 628, 739)),
    'recipe_arrow': ('05-recipes.png', (1100, 472, 1149, 515)),
}
EXCLUSIONS = {
    'hud_axis': [[25,10,77,269]], 'hud_day': [[29,9,105,43]],
    'hud_recipe': [[15,66,88,102]], 'hud_relationship': [[15,51,86,90]],
    'hud_portrait': [[31,9,78,43],[9,48,102,181]],
    'relation_outer': [[48,61,1080,557],[441,0,663,24]],
    'relation_title': [[40,9,185,49]],
    'relation_selected': [[7,8,146,127],[158,45,246,97]],
    'relation_normal': [[10,8,145,127],[157,44,244,99]],
    'relation_portrait': [[20,18,300,445]],
    'relation_detail': [[32,26,359,79],[42,110,330,281],[34,313,373,384],[285,438,398,484]],
    'relation_close': [[25,11,83,48]],
    'recipe_outer': [[24,41,350,502],[358,104,1121,465],[945,501,1090,571],[453,0,675,24]],
    'recipe_title': [[66,16,159,51]], 'recipe_heading': [[81,10,208,43]],
    'recipe_selected': [[40,13,115,99],[130,26,231,79]],
    'recipe_normal': [[36,12,119,100],[124,32,221,81]],
    'recipe_close': [[23,10,97,50]], 'recipe_divider': [], 'recipe_arrow': [],
}

def references():
    target = OUT / 'reference-crops'
    target.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name, (file, box) in PARTS.items():
        image = Image.open(REFERENCES / file).convert('RGB').crop(box)
        image.save(target / (name + '.png'))
        manifest[name] = {'source': str((REFERENCES/file).relative_to(ROOT)), 'box': box,
                          'size': image.size, 'status': 'not_reviewed',
                          'exclusions': EXCLUSIONS.get(name, []), 'candidate': None}
    (OUT/'components.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')

def ssim_blocks(a, b):
    scores = []
    for y in range(0, a.shape[0]-7, 8):
        for x in range(0, a.shape[1]-7, 8):
            aa, bb = a[y:y+8,x:x+8], b[y:y+8,x:x+8]
            ma, mb = aa.mean(), bb.mean()
            va, vb = aa.var(), bb.var()
            cov = ((aa-ma)*(bb-mb)).mean()
            scores.append(((2*ma*mb+6.5025)*(2*cov+58.5225))/((ma*ma+mb*mb+6.5025)*(va+vb+58.5225)))
    return float(np.mean(scores)) if scores else 0.0

def compare(name, candidate, exclusions):
    ref = Image.open(OUT/'reference-crops'/(name+'.png')).convert('RGB')
    raw = Image.open(candidate).convert('RGBA')
    # Reference-derived pieces keep the original crop dimensions. Compare them at the
    # same coordinates without trimming transparent edges or resampling source pixels.
    if raw.size == ref.size:
        composite = raw
        alignment = 'same_coordinates_no_resample'
    else:
        used = raw.getchannel('A').point(lambda x: 255 if x >= 128 else 0).getbbox()
        raw = raw.crop(used) if used else raw
        # Generated candidates permit only one uniform contain operation.
        scale = min(ref.width/raw.width, ref.height/raw.height)
        fit = raw.resize((max(1,round(raw.width*scale)),max(1,round(raw.height*scale))),Image.Resampling.LANCZOS)
        composite = Image.new('RGBA', ref.size, (29,27,24,255))
        composite.alpha_composite(fit, ((ref.width-fit.width)//2,(ref.height-fit.height)//2))
        alignment = 'uniform_contain'
    a, b = np.asarray(ref,dtype=float), np.asarray(composite.convert('RGB'),dtype=float)
    mask = np.ones(a.shape[:2], dtype=bool)
    for x0,y0,x1,y1 in exclusions:
        mask[y0:y1,x0:x1] = False
    error = np.abs(a-b)
    mae = float(error[mask].mean())
    percentile = float(np.percentile(error[mask],95))
    # SSIM samples are independent unmasked 8x8 blocks only.
    grey_a, grey_b = a.mean(2), b.mean(2)
    ss = []
    for y in range(0,ref.height-7,8):
        for x in range(0,ref.width-7,8):
            if mask[y:y+8,x:x+8].all():
                ss.append(ssim_blocks(grey_a[y:y+8,x:x+8],grey_b[y:y+8,x:x+8]))
    ssim = float(np.mean(ss)) if ss else 0.0
    passing = mae <= 8 and percentile <= 24 and ssim >= .90
    heat = np.zeros_like(a,dtype=np.uint8)
    heat[:,:,0] = np.clip(error.mean(2)*5,0,255).astype(np.uint8)
    heat[~mask] = (42,66,88)
    contact = Image.new('RGB',(ref.width*3,ref.height))
    contact.paste(ref,(0,0)); contact.paste(composite.convert('RGB'),(ref.width,0))
    contact.paste(Image.fromarray(heat),(ref.width*2,0))
    directory = OUT/'comparisons'; directory.mkdir(exist_ok=True)
    comparison_id = name+'--'+Path(candidate).stem
    contact.save(directory/(comparison_id+'.png'))
    result = {'component':name,'candidate':str(candidate),'mae':mae,'p95_error':percentile,
              'ssim_8x8':ssim,'compared_fraction':float(mask.mean()),'exclusions':exclusions,
              'numeric_gate':'pass' if passing else 'fail','edge_review':'pending',
              'hierarchy_review':'pending','approved':False,
              'candidate_sha256':hashlib.sha256(Path(candidate).read_bytes()).hexdigest(),
              'comparison':comparison_id+'.png','alignment':alignment}
    (directory/(comparison_id+'.json')).write_text(json.dumps(result,indent=2),encoding='utf8')
    print(json.dumps(result))
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--prepare',action='store_true')
    parser.add_argument('--part'); parser.add_argument('--candidate',type=Path)
    parser.add_argument('--exclude',default=None)
    args=parser.parse_args()
    if args.prepare: references(); print('Reference crops prepared')
    if args.part:
        locked=json.loads((OUT/'components.json').read_text(encoding='utf8'))
        exclusions=locked[args.part]['exclusions'] if args.exclude is None else json.loads(args.exclude)
        compare(args.part,args.candidate,exclusions)

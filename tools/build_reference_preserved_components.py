"""Build UI pieces that preserve every visible source pixel outside declared occlusions."""
from pathlib import Path
import json
import hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import reference_component_gate as gate

ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / 'outputs/ui-reference-gate-20260922'
REF = GATE / 'reference-crops'
OUT = ROOT / 'assets/art/ui/reference_preserved_20260922'
HUD = ROOT / 'assets/art/ui/reference_parts_20260922/hud'
JOURNAL = ROOT / 'assets/art/ui/reference_parts_20260922/journal'
OUT.mkdir(parents=True, exist_ok=True)

def alpha_bbox(image):
    return image.getchannel('A').point(lambda a:255 if a >= 128 else 0).getbbox()

def fit_candidate(path, size, structured=False):
    image = Image.open(path).convert('RGBA')
    box = alpha_bbox(image)
    image = image.crop(box) if box else image
    if not structured:
        # Infill uses only uninterrupted paper from the candidate center. Candidate
        # outer edges must never appear inside a cleared text/content rectangle.
        inset_x=max(1,round(image.width*.27)); inset_y=max(1,round(image.height*.27))
        image=image.crop((inset_x,inset_y,image.width-inset_x,image.height-inset_y))
    scale = max(size[0]/image.width,size[1]/image.height)
    image = image.resize((round(image.width*scale),round(image.height*scale)),Image.Resampling.LANCZOS)
    x=(image.width-size[0])//2; y=(image.height-size[1])//2
    return image.crop((x,y,x+size[0],y+size[1]))

def match_color(fill, reference, sample_mask):
    src=np.asarray(fill.convert('RGB'),dtype=np.float32)
    ref=np.asarray(reference.convert('RGB'),dtype=np.float32)
    alpha=np.asarray(fill.getchannel('A'),dtype=np.float32)/255
    valid=(alpha>.5)&sample_mask
    if valid.sum()<20:
        return fill
    result=src.copy()
    for channel in range(3):
        s=src[:,:,channel][valid]; r=ref[:,:,channel][sample_mask]
        sdev=max(float(s.std()),4); rdev=max(float(r.std()),4)
        result[:,:,channel]=(src[:,:,channel]-float(s.mean()))*(rdev/sdev)+float(r.mean())
    output=Image.fromarray(np.uint8(np.clip(result,0,255)),'RGB').convert('RGBA')
    output.putalpha(fill.getchannel('A'))
    return output

def regular_mask(size, cut=4, radius=0):
    w,h=size
    points=[(cut,0),(w-cut-1,0),(w-1,cut),(w-1,h-cut-1),(w-cut-1,h-1),(cut,h-1),(0,h-cut-1),(0,cut)]
    mask=Image.new('L',size,0); ImageDraw.Draw(mask).polygon(points,fill=255)
    if radius:
        mask=mask.filter(ImageFilter.GaussianBlur(radius))
    return mask

def rect_mask(size, rects, feather=2):
    mask=Image.new('L',size,0); draw=ImageDraw.Draw(mask)
    for rect in rects: draw.rectangle(rect,fill=255)
    return mask.filter(ImageFilter.GaussianBlur(feather)) if feather else mask

def tiled_source(reference, patch_rect):
    patch=reference.crop(patch_rect).convert('RGBA')
    canvas=Image.new('RGBA',reference.size)
    for y in range(0,canvas.height,patch.height):
        for x in range(0,canvas.width,patch.width): canvas.alpha_composite(patch,(x,y))
    return canvas

def local_match(fill, reference, rect):
    x0,y0,x1,y1=rect
    patch=np.asarray(fill.crop(rect).convert('RGB'),dtype=np.float32)
    grown=(max(0,x0-5),max(0,y0-5),min(reference.width,x1+5),min(reference.height,y1+5))
    around=np.asarray(reference.crop(grown).convert('RGB'),dtype=np.float32)
    inner=np.zeros(around.shape[:2],dtype=bool)
    inner[y0-grown[1]:y1-grown[1],x0-grown[0]:x1-grown[0]]=True
    ring=around[~inner]
    if ring.size:
        delta=np.median(ring,axis=0)-np.median(patch.reshape(-1,3),axis=0)
        patch=np.clip(patch+delta,0,255)
    return Image.fromarray(np.uint8(patch),'RGB').convert('RGBA')

def preserve_component(name, reference_name, candidate, erase, cut=4, preserve=(), feather=2, structured=False, source_patch=None):
    ref=Image.open(REF/(reference_name+'.png')).convert('RGBA')
    fill=tiled_source(ref,source_patch) if source_patch else fit_candidate(candidate,ref.size,structured)
    assembled=ref.copy()
    erase_alpha=Image.new('L',ref.size,0)
    for rect in erase:
        x0,y0,x1,y1=rect
        patch=fill.crop(rect) if source_patch else local_match(fill,ref,rect)
        mask=rect_mask((x1-x0,y1-y0),[(0,0,x1-x0,y1-y0)],feather)
        assembled.alpha_composite(patch,(x0,y0))
        # Restore the source outside the declared rectangle after compositing.
        full=Image.new('L',ref.size,0); full.paste(mask,(x0,y0)); erase_alpha=Image.fromarray(np.maximum(np.asarray(erase_alpha),np.asarray(full)).astype('uint8'),'L')
    assembled=Image.composite(assembled,ref,erase_alpha)
    assembled.putalpha(regular_mask(ref.size,cut,0.55))
    output=OUT/(name+'.png'); assembled.save(output)
    ref_rgb=np.asarray(ref.convert('RGB'))
    out_rgb=np.asarray(assembled.convert('RGB'))
    untouched=np.asarray(erase_alpha)<2
    exact=float(np.mean(np.all(ref_rgb[untouched]==out_rgb[untouched],axis=1))) if untouched.any() else 1
    return {'file':output.name,'source':reference_name+'.png','size':ref.size,'erase':erase,'preserve':preserve,
            'visible_source_exact_fraction':exact,'sha256':hashlib.sha256(output.read_bytes()).hexdigest()}

def extracted_symbol(name, reference_name, keep_rect, threshold=125):
    source=Image.open(REF/(reference_name+'.png')).convert('RGBA').crop(keep_rect)
    rgb=np.asarray(source.convert('RGB'))
    light=rgb.mean(2)
    warm=(rgb[:,:,0]>=rgb[:,:,2]-8)
    alpha=np.uint8(np.clip((light-threshold)*8,0,255))*warm.astype('uint8')
    result=source.copy(); result.putalpha(Image.fromarray(alpha,'L'))
    # Keep original crop coordinates so the runtime and gate never resample it.
    output=OUT/(name+'.png'); result.save(output)
    return {'file':output.name,'source':reference_name+'.png','source_rect':keep_rect,'size':result.size,
            'sha256':hashlib.sha256(output.read_bytes()).hexdigest()}

def whole_candidate_component(name, reference_name, candidate, gains=(1.0,1.0,1.0)):
    """Use one coherent generated paper piece and crop it uniformly to target size.

    This avoids rectangular inpaint islands and preserves the authored brush scale;
    no center tile or nine-slice is used.
    """
    target=Image.open(REF/(reference_name+'.png')).convert('RGBA')
    result=fit_candidate(candidate,target.size,structured=True)
    if gains != (1.0,1.0,1.0):
        pixels=np.asarray(result).copy()
        pixels[:,:,:3]=np.uint8(np.clip(pixels[:,:,:3].astype(np.float32)*np.asarray(gains,dtype=np.float32),0,255))
        result=Image.fromarray(pixels,'RGBA')
    output=OUT/(name+'.png')
    result.save(output)
    return {
        'file':output.name,
        'source':reference_name+'.png',
        'size':target.size,
        'method':'single_coherent_whole_piece',
        'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
    }

def sized_whole_candidate(name, candidate, size, gains=(1.0,1.0,1.0)):
    result=fit_candidate(candidate,size,structured=True)
    if gains != (1.0,1.0,1.0):
        pixels=np.asarray(result).copy()
        pixels[:,:,:3]=np.uint8(np.clip(pixels[:,:,:3].astype(np.float32)*np.asarray(gains,dtype=np.float32),0,255))
        result=Image.fromarray(pixels,'RGBA')
    output=OUT/(name+'.png')
    result.save(output)
    return {
        'file':output.name,
        'size':size,
        'method':'single_coherent_whole_piece',
        'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
    }

def preserve_with_whole_fill(name, reference_name, candidate, erase, gains=(1.0,1.0,1.0), feather=3):
    """Keep every source pixel outside locked dynamic areas.

    A single aligned candidate supplies all cleared regions.  The candidate's
    alpha defines the visible paper silhouette, while the source RGB remains in
    place for exact edge and static-decoration comparison.
    """
    ref=Image.open(REF/(reference_name+'.png')).convert('RGBA')
    fill=fit_candidate(candidate,ref.size,structured=True)
    if gains != (1.0,1.0,1.0):
        pixels=np.asarray(fill).copy()
        pixels[:,:,:3]=np.uint8(np.clip(pixels[:,:,:3].astype(np.float32)*np.asarray(gains,dtype=np.float32),0,255))
        fill=Image.fromarray(pixels,'RGBA')
    assembled=ref.copy()
    erased=Image.new('L',ref.size,0)
    for rect in erase:
        x0,y0,x1,y1=rect
        patch=local_match(fill,ref,rect)
        w,h=x1-x0,y1-y0
        if feather>0:
            yy,xx=np.mgrid[0:h,0:w]
            distance=np.minimum.reduce([xx,yy,w-1-xx,h-1-yy]).astype(np.float32)
            alpha=np.uint8(np.clip(190.0+65.0*distance/max(float(feather),1.0),0,255))
            mask=Image.fromarray(alpha,'L')
        else:
            mask=Image.new('L',(w,h),255)
        base=assembled.crop(rect)
        assembled.paste(Image.composite(patch,base,mask),(x0,y0))
        erased.paste(255,(x0,y0,x1,y1))
    assembled.putalpha(fill.getchannel('A'))
    output=OUT/(name+'.png')
    assembled.save(output)
    ref_rgb=np.asarray(ref.convert('RGB'))
    out_rgb=np.asarray(assembled.convert('RGB'))
    untouched=np.asarray(erased)==0
    exact=float(np.mean(np.all(ref_rgb[untouched]==out_rgb[untouched],axis=1))) if untouched.any() else 1.0
    return {
        'file':output.name,
        'source':reference_name+'.png',
        'size':ref.size,
        'erase':erase,
        'method':'locked_source_with_single_coherent_fill',
        'visible_source_exact_fraction':exact,
        'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
    }

manifest={'status':'whole_piece_layout_candidate','method':'single coherent whole-paper components; no tiled or rectangular infill','components':[]}
add=manifest['components'].append

# HUD: preserve original silhouettes/icons; remove only labels, time state and old portrait.
add(preserve_component('hud-axis-paper','hud_axis',HUD/'axis-paper-candidate.png',gate.EXCLUSIONS['hud_axis'],cut=5))
add(preserve_component('hud-recipe-button','hud_recipe',HUD/'recipe-button-candidate-v2.png',gate.EXCLUSIONS['hud_recipe'],cut=5))
add(preserve_component('hud-relationship-button','hud_relationship',HUD/'relationship-button-candidate-v2.png',gate.EXCLUSIONS['hud_relationship'],cut=5))
add(preserve_component('hud-avatar-frame','hud_portrait',HUD/'avatar-frame-candidate-v2.png',gate.EXCLUSIONS['hud_portrait'],cut=4,structured=True))
add(extracted_symbol('hud-sun','hud_axis',(22,8,80,61),115))
add(extracted_symbol('hud-moon','hud_axis',(24,216,80,275),115))
add(extracted_symbol('hud-recipe-icon','hud_recipe',(20,7,83,67),115))
add(extracted_symbol('hud-relationship-icon','hud_relationship',(21,5,80,53),115))

# Journal: one coherent whole image per paper component.  Runtime text and
# portraits remain separate, but the paper edge and its inner brush field are
# never assembled from unrelated rectangular patches.
add(preserve_with_whole_fill('journal-outer','relation_outer',JOURNAL/'journal-outer-candidate-v1.png',gate.EXCLUSIONS['relation_outer'],(0.82,0.86,0.89)))
add(preserve_with_whole_fill('journal-title','relation_title',JOURNAL/'journal-title-candidate-v3.png',gate.EXCLUSIONS['relation_title']))
add(preserve_with_whole_fill('journal-selected-row','relation_selected',JOURNAL/'journal-selected-row-candidate-v2.png',gate.EXCLUSIONS['relation_selected'],(0.89,1.0,0.98)))
add(preserve_with_whole_fill('journal-normal-row','relation_normal',JOURNAL/'journal-normal-row-candidate-v1.png',gate.EXCLUSIONS['relation_normal'],(0.89,0.84,0.83)))
add(sized_whole_candidate('journal-thumbnail-paper',JOURNAL/'journal-close-candidate-v2.png',(139,119),(0.78,0.78,0.77)))
add(preserve_with_whole_fill('journal-portrait-paper','relation_portrait',ROOT/'assets/art/ui/whole_refinement_20260922/portrait-whole-v1.png',gate.EXCLUSIONS['relation_portrait'],(1.20,1.20,1.24)))
add(preserve_with_whole_fill('journal-detail-paper','relation_detail',JOURNAL/'journal-detail-candidate-v1.png',gate.EXCLUSIONS['relation_detail'],(1.12,1.08,1.12)))
add(preserve_with_whole_fill('journal-close','relation_close',JOURNAL/'journal-close-candidate-v2.png',gate.EXCLUSIONS['relation_close'],(0.87,0.85,0.83)))
add(preserve_with_whole_fill('recipe-outer','recipe_outer',JOURNAL/'recipe-outer-candidate-v1.png',gate.EXCLUSIONS['recipe_outer'],(0.96,1.0,1.06)))
add(preserve_with_whole_fill('recipe-title','recipe_title',JOURNAL/'journal-title-candidate-v3.png',gate.EXCLUSIONS['recipe_title']))
add(preserve_with_whole_fill('recipe-heading','recipe_heading',JOURNAL/'journal-normal-row-candidate-v1.png',gate.EXCLUSIONS['recipe_heading'],(0.89,0.84,0.83)))
add(preserve_with_whole_fill('recipe-selected-row','recipe_selected',JOURNAL/'journal-selected-row-candidate-v2.png',gate.EXCLUSIONS['recipe_selected'],(0.89,1.0,0.98)))
add(preserve_with_whole_fill('recipe-normal-row','recipe_normal',JOURNAL/'journal-normal-row-candidate-v1.png',gate.EXCLUSIONS['recipe_normal'],(0.89,0.84,0.83)))
add(preserve_with_whole_fill('recipe-close','recipe_close',JOURNAL/'journal-close-candidate-v2.png',gate.EXCLUSIONS['recipe_close'],(0.76,0.74,0.72)))
add(extracted_symbol('recipe-divider','recipe_divider',(0,0,50,490),80))
add(extracted_symbol('recipe-arrow','recipe_arrow',(0,0,49,43),85))

(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'components':len(manifest['components']),'method':manifest['method']}))

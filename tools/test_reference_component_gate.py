"""Control cases for visual gate fail-closed behavior."""
import contextlib
import io
import tempfile
from pathlib import Path
from PIL import Image
import reference_component_gate as gate

with tempfile.TemporaryDirectory() as folder:
    previous=gate.OUT
    gate.OUT=Path(folder)
    (gate.OUT/'reference-crops').mkdir()
    original=Image.open(previous/'reference-crops/hud_recipe.png').convert('RGB')
    original.save(gate.OUT/'reference-crops/control.png')
    original.save(gate.OUT/'same.png')
    Image.new('RGB',original.size,(180,160,40)).save(gate.OUT/'wrong.png')
    with contextlib.redirect_stdout(io.StringIO()):
        same=gate.compare('control',gate.OUT/'same.png',[])
        wrong=gate.compare('control',gate.OUT/'wrong.png',[])
    assert same['numeric_gate']=='pass' and same['mae']==0 and same['ssim_8x8']==1
    assert same['approved'] is False and same['edge_review']=='pending'
    assert wrong['numeric_gate']=='fail' and wrong['approved'] is False
    gate.OUT=previous
print('PASS identical image numeric control')
print('PASS numeric control cannot approve artwork')
print('PASS different image remains rejected')

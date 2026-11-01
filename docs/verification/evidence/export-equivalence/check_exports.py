"""Focused F30 export checks; run after verify_rom.tcl with project Python."""
import csv
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT))

def run(script, *args):
    result = subprocess.run([sys.executable, str(ROOT / script), *map(str, args)],
                            cwd=HERE, capture_output=True, text=True, check=True)
    (HERE / (Path(script).stem + '.log')).write_text(result.stdout + result.stderr)

def words(path):
    rows = [x.strip() for x in path.read_text().splitlines()
            if x.strip() and not x.startswith('//')]
    assert all(re.fullmatch('[0-9A-Fa-f]{4}', x) for x in rows), path
    return [int(x, 16) for x in rows]

run('tools/win_gen/gen_hann_coeffs.py', '--out-prefix', HERE / 'hann_256')
run('tools/win_gen/gen_hann_coeffs.py', '--norm', 'cola', '--out-prefix', HERE / 'hann_cola')
run('tools/profile_gen/gen_default_tables.py', '--out-dir', HERE / 'modes')
transcript = (HERE / 'vivado/f30_rom.sim/sim_1/behav/xsim/simulate.log').read_text()
assert 'F30_ROM_DUMP_PASS count=256 LEN=256 WIDTH=16' in transcript
assert not re.search(r'(?im)^\s*(?:error|fatal):', transcript)
assert re.search(r'(?m)^F30_SIM_CONTRACT_PASS\s*$', (HERE / 'vivado.log').read_text())
rows = [line.split() for line in (HERE / 'vivado/f30_rom.sim/sim_1/behav/xsim/rom_words.txt').read_text().splitlines()]
assert len(rows) == 256
assert [int(r[0]) for r in rows] == list(range(256))
actual = [int(r[1], 16) for r in rows]
expected = words(HERE / 'hann_256.hex')
assert len(expected) == 256
with (HERE / 'hann_comparison.csv').open('w', newline='') as stream:
    writer = csv.writer(stream)
    writer.writerow(['address', 'rtl_hex', 'python_hex', 'match'])
    writer.writerows((i, f'{a:04X}', f'{b:04X}', a == b)
                     for i, (a, b) in enumerate(zip(actual, expected)))
assert actual == expected, 'ROM/generator mismatch; see CSV; do not change RTL to fit export'
assert words(HERE / 'hann_cola.hex') == actual
# Independent parsing avoids reusing the mode exporter's parser as its oracle.
source = (ROOT / 'fpga/rtl/ctrl/mode_ctrl.sv').read_text()
source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
mode_rows = []
for mode in ('general', 'speech', 'music', 'hearing'):
    body = re.search(r'GAIN_' + mode.upper() + r"\s*\[0:127\]\s*=\s*'\{(.*?)\}", source, re.S)[1]
    embedded = [int(x.strip()) for x in body.split(',')]
    exported = words(HERE / f'modes/gain_table_{mode}.hex')
    assert len(embedded) == len(exported) == 128
    assert embedded == exported
    mode_rows.extend((mode, i, a, b) for i, (a, b) in enumerate(zip(embedded, exported)))
with (HERE / 'mode_comparison.csv').open('w', newline='') as stream:
    writer = csv.writer(stream)
    writer.writerow(['mode', 'address', 'rtl_word', 'export_word'])
    writer.writerows(mode_rows)
manifest = json.loads((HERE / 'modes/gain_tables_manifest.json').read_text())
assert manifest['mode_ids'] == dict(general=0, speech=1, music=2, hearing=3)
assert manifest['source_sha256'] == hashlib.sha256((ROOT / manifest['source']).read_bytes()).hexdigest()
paths = ['fpga/rtl/pkg/auris_pkg.sv', 'fpga/rtl/dsp/window_rom.sv',
         'fpga/rtl/ctrl/mode_ctrl.sv', 'tools/win_gen/gen_hann_coeffs.py',
         'tools/profile_gen/gen_default_tables.py', 'tools/common/formats.py',
         'tools/common/constants.py', 'fpga/scripts/simulation_common.tcl',
         '.github/workflows/ci.yml', '.github/workflows/release.yml',
         'tools/README.md', 'fpga/scripts/sim_window_apply.tcl']
paths += [str(p.relative_to(ROOT)).replace('\\', '/') for p in HERE.glob('*')
          if p.suffix in ('.py', '.sv', '.tcl')]
(HERE / 'source_sha256.json').write_text(json.dumps({p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest()
                                                  for p in paths}, indent=2) + '\n')
print('F30_HANN_EQUIVALENCE_PASS: 256/256 exact ordered 16-bit words; periodic none and cola')
print('F30_MODE_EXPORT_PASS: 512/512 embedded words; IDs and source hash exact')

# Exercise real CLI defaults from outside repository root, as Make/release do
# without explicit output arguments. Do not infer defaults from help text.
run('tools/win_gen/gen_hann_coeffs.py')
run('tools/profile_gen/gen_default_tables.py')
assert words(ROOT / 'fpga/generated/hann_256.hex') == actual
for mode in ('general', 'speech', 'music', 'hearing'):
    assert words(ROOT / f'fpga/generated/gain_table_{mode}.hex') == words(HERE / f'modes/gain_table_{mode}.hex')
assert (ROOT / 'fpga/generated/hann_256.coe').stat().st_size
assert (ROOT / 'fpga/generated/hann_256.json').stat().st_size
release = (ROOT / '.github/workflows/release.yml').read_text(encoding='utf-8')
assert 'fpga/generated/*.json' in release
assert 'for FPGA ROM initialisation' not in release
assert 'as BRAM' not in release
import shutil
stage = HERE / 'release_stage/generated'
stage.mkdir(parents=True, exist_ok=True)
for suffix in ('hex', 'coe', 'json'):
    files = list((ROOT / 'fpga/generated').glob('*.' + suffix))
    assert files
    for path in files:
        shutil.copyfile(path, stage / path.name)
for name in ('hann_256.hex', 'hann_256.coe', 'hann_256.json', 'gain_tables_manifest.json',
             *(f'gain_table_{mode}.hex' for mode in ('general', 'speech', 'music', 'hearing'))):
    assert (stage / name).read_bytes() == (ROOT / 'fpga/generated' / name).read_bytes()
print('F30_PATH_CONTRACT_PASS: outside-root defaults match CI/Make/release paths; local release staging includes provenance')

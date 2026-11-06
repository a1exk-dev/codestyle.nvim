import os, pathlib, sys
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, os.path.expanduser("~/Projects/phpstorm-editorconfig/tools/behavior"))
import fmt
from schemes import SCHEMES, plain_scheme
fmt.ALLOW_SKIPPED = True
src = {}
for sub in ("inputs", "controls"):
    for f in sorted((HERE / sub).iterdir()):
        src[f.name] = f.read_text()
res = fmt.run_many({s: plain_scheme(l) for s, l in SCHEMES.items()}, src, workers=2, log=lambda *a: print(*a, flush=True))
for s, outs in res.items():
    od = HERE / "cli" / s
    od.mkdir(parents=True, exist_ok=True)
    for n, t in outs.items():
        (od / n).write_text(t)
print("done")

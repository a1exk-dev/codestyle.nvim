#!/usr/bin/env python3
"""Reformat Code in the running IDE: every input and control under every scheme. Results in ide/<scheme>/."""
import atexit, json, os, shutil, subprocess, sys, time, select
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from schemes import SCHEMES, project_xml
UI = os.path.expanduser("~/Projects/phpstorm-editorconfig/tools/gui/ui")
PROJ = os.path.expanduser("~/phpstorm-editorconfig")
CS = f"{PROJ}/.idea/codeStyles"
RUN = f"{PROJ}/gui3/run"
ENV = dict(os.environ, UI_WINDOW="phpstorm-editorconfig")


def ui(*a):
    r = subprocess.run([UI, *a], env=ENV, capture_output=True)
    if r.returncode:
        raise RuntimeError("ui failed: " + r.stderr.decode()[-300:])


def active_title():
    return json.loads(subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True).stdout or "{}").get("title", "")


def read(p):
    with open(p, newline="") as f:
        return f.read()


def wait_change(path, before, timeout):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if read(path) != before:
            time.sleep(0.5)
            return True
        time.sleep(0.25)
    return False


bak = {n: (read(f"{CS}/{n}") if os.path.exists(f"{CS}/{n}") else None) for n in ("Project.xml", "codeStyleConfig.xml")}


def restore():
    for n, v in bak.items():
        p = f"{CS}/{n}"
        if v is None:
            if os.path.exists(p): os.remove(p)
        else:
            open(p, "w").write(v)


atexit.register(restore)


def write_settings(xml):
    w = subprocess.Popen(["inotifywait", "-m", "-q", "-e", "close_nowrite", "--format", "%f", CS], stdout=subprocess.PIPE, text=True)
    try:
        time.sleep(0.3)
        open(f"{CS}/Project.xml", "w").write(xml)
        t0, seen = time.time(), False
        while time.time() - t0 < 20 and not seen:
            if select.select([w.stdout], [], [], 0.5)[0]:
                seen = w.stdout.readline().strip() == "Project.xml"
        print("  settings read" if seen else "  WARN: Project.xml not re-read in 20 s", flush=True)
        time.sleep(2)
    finally:
        w.terminate()


def reformat(src, out, tag):
    name = f"{tag}_{os.path.basename(src)}"
    path = f"{RUN}/{name}"
    shutil.copy(src, path)
    before = read(path)
    subprocess.run(["/opt/phpstorm/bin/phpstorm", path], capture_output=True)
    t0 = time.time()
    while name not in active_title() and time.time() - t0 < 25:
        time.sleep(0.3)
    time.sleep(1.0)
    changed = False
    for attempt in range(2):
        ui("click", "1700", "600", "key", "ctrl+Home", "sleep", "0.3", "key", "ctrl+alt+l", "sleep", "2.5", "key", "ctrl+s", "sleep", "0.3")
        if wait_change(path, before, 3):
            changed = True
            break
        ui("key", "Escape")
    if os.environ.get("SHOTS"):
        ui("wshot", out + ".png")
    shutil.copy(path, out)
    ui("key", "Escape", "key", "ctrl+F4", "sleep", "0.5")
    return changed


PROBE = {"js8_css2": ("ctl.js", "\n        if (a)"), "html2_vue4_blade2": ("ctl.html", "\n  <p>x"),
         "php8": ("ctl.php", "\n        $b"), "default": ("ctl.php", "\n    $b")}


def main():
    os.makedirs(RUN, exist_ok=True)
    open(f"{CS}/codeStyleConfig.xml", "w").write(
        '<component name="ProjectCodeStyleConfiguration">\n  <state>\n    <option name="USE_PER_PROJECT_SETTINGS" value="true" />\n  </state>\n</component>\n')
    only = sys.argv[1:] or list(SCHEMES)
    log = {}
    for s in only:
        print(s, flush=True)
        write_settings(project_xml(SCHEMES[s]))
        if s in PROBE:
            f, want = PROBE[s]
            for att in range(10):
                reformat(f"{HERE}/controls/{f}", f"{HERE}/probe.out", f"probe{att}_{int(time.time())}")
                if want in read(f"{HERE}/probe.out"):
                    print(f"  loaded after {att + 1} probe(s)", flush=True)
                    break
                time.sleep(5)
            else:
                sys.exit("scheme never loaded")
        od = f"{HERE}/ide/{s}"
        os.makedirs(od, exist_ok=True)
        for sub in ("inputs", "controls"):
            for f in sorted(os.listdir(f"{HERE}/{sub}")):
                ch = reformat(f"{HERE}/{sub}/{f}", f"{od}/{f}", f"{s}_{int(time.time())}")
                log[f"{s}/{f}"] = ch
                print(f"  {f}: {'changed' if ch else 'UNCHANGED'}", flush=True)
    json.dump(log, open(f"{HERE}/ide/run_{int(time.time())}.json", "w"), indent=1)


main()

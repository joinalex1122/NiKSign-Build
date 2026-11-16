"""Download exact upstream snapshots of the three reference-only projects.
Usage: python3 scripts/fetch-reference-sources.py TrollFools ellekit optool
Not called by the build. Does not compile, install or execute upstream code.
"""
from pathlib import Path
import argparse, json, subprocess
r = Path(__file__).resolve().parents[1]
registry = {x['name']:x for x in json.loads((r/'Native/Licenses/components.json').read_text()) if x['status']=='reference'}
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('names', nargs='+', choices=sorted(registry))
args=p.parse_args()
for name in args.names:
    entry=registry[name]; destination=r/'.reference-sources'/name
    if destination.exists():
        revision=subprocess.check_output(['git','-C',str(destination),'rev-parse','HEAD'],text=True).strip()
        if revision != entry['revision']: raise SystemExit(f'{name}: existing checkout differs; preserved without modification.')
        print(name, revision, 'already available'); continue
    destination.mkdir(parents=True)
    subprocess.run(['git','init',str(destination)],check=True)
    subprocess.run(['git','-C',str(destination),'remote','add','origin',entry['repository']+'.git'],check=True)
    subprocess.run(['git','-C',str(destination),'fetch','--depth','1','origin',entry['revision']],check=True)
    subprocess.run(['git','-C',str(destination),'checkout','--detach','FETCH_HEAD'],check=True)
    print(name,entry['revision'],'downloaded; submodules are not fetched; not included in NiKSign build.')

"""Maintainer import: export ONLY committed static inputs into a fresh instance.
No fetch, game launch, DB/saves, working-tree files, runtime keys or customer data.
Usage: python stage-data.py --help. Git and Python 3.9+, no extra Python packages.
"""
import argparse, hashlib, os, subprocess, tarfile, tempfile, shutil
from pathlib import Path, PurePosixPath
SRC="0fac870873a35e88b9f969aa1b242a832b602005"
RES="402e95270010df5929f51cca8652362ca3e5c07a"
NAMES="49a6544a6c6ae36089cb42fa591fc46f01de8bcf"
def export(repo,rev,selected,dest):
    if dest.exists(): raise RuntimeError(f'Refusing existing directory: {dest}')
    dest.parent.mkdir(parents=True,exist_ok=True)
    repo=repo.resolve(strict=True)
    if subprocess.check_output(['git','-C',str(repo),'rev-parse','--verify',rev+'^{commit}'],text=True).strip()!=rev:
        raise RuntimeError('Unexpected source commit')
    with tempfile.TemporaryDirectory(dir=dest.parent,prefix='.arena-import-') as tmp:
        tree=Path(tmp)/'files';tree.mkdir()
        with subprocess.Popen(['git','-C',str(repo),'archive','--format=tar',rev,'--',*selected],stdout=subprocess.PIPE) as proc:
            try:
                with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:
                    for member in tar:
                        p=PurePosixPath(member.name)
                        if p.is_absolute() or any(t in ('.','..') or ':' in t or '\\' in t for t in p.parts): raise ValueError('Unsafe archive path')
                        if member.isdir(): continue
                        if not member.isfile(): raise ValueError('Non-regular archive entry')
                        target=tree.joinpath(*p.parts)
                        target.parent.mkdir(parents=True,exist_ok=True)
                        with target.open('xb') as out, tar.extractfile(member) as inp: shutil.copyfileobj(inp,out)
            finally: proc.stdout.close()
            if proc.wait(): raise RuntimeError('git archive failed')
        if not any(tree.iterdir()): raise RuntimeError('Empty source export')
        tree.rename(dest)
def checkout_entries(repo,rev,selected,dest):
    # git archive may materialize unrelated objects in a sparse clone; copy only listed
    # paths and validate the Git blob ID before writing. No smudge filters or hooks.
    repo=repo.resolve(strict=True)
    raw=subprocess.check_output(['git','-C',str(repo),'ls-tree','-rz',rev,'--',*selected])
    for item in raw.split(b'\0'):
        if not item: continue
        meta,name=item.split(b'\t',1); mode,typ,expected=meta.decode().split(); p=PurePosixPath(name.decode())
        if mode!='100644' or typ!='blob' or p.is_absolute() or any(t in ('.','..') or ':' in t or chr(92) in t for t in p.parts):raise ValueError('Unsafe tree entry')
        f=repo.joinpath(*p.parts)
        if not f.resolve(strict=True).is_relative_to(repo): raise ValueError('Unexpected symlink')
        data=f.read_bytes()
        def blob(x): return hashlib.sha1(b'blob '+str(len(x)).encode()+b'\0'+x).hexdigest()
        if blob(data)!=expected:data=data.replace(b'\r\n',b'\n')
        if blob(data)!=expected:raise ValueError(f'Checkout does not match pinned blob: {p}')
        target=dest.joinpath(*p.parts);target.parent.mkdir(parents=True,exist_ok=True)
        with target.open('xb') as out:out.write(data)
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for n in ('root','source','resources','name-data'):ap.add_argument('--'+n,type=Path,required=True)
    os.environ["GIT_NO_LAZY_FETCH"]="1"
    a=ap.parse_args(); root=a.root.resolve(strict=True)
    for repo in (a.source,a.resources,a.name_data):
        if root==repo.resolve() or repo.resolve() in root.parents: raise ValueError('Use a separate, empty output instance')
    server=root/'server'
    for item in ('data','webstatic','lua','resources'):
        if (server/item).exists():raise ValueError('Existing server inputs; use a fresh staging directory')
    if (root/'source').exists() or (root/'name-data').exists():raise ValueError('Existing source inputs')
    # Build and validate all three exports before installing anything.
    with tempfile.TemporaryDirectory(dir=root,prefix='.arena-static-') as tmp:
        t=Path(tmp);game='src/main/java/emu/grasscutter/GameConstants.java'
        export(a.source,SRC,['data','webstatic','lua',game,'LICENSE'],t/'source')
        export(a.resources,RES,['ExcelBinOutput','BinOutput','Scripts','Server','ScriptSceneData','TextMap','LICENSE','README.md'],t/'resources')
        checkout_entries(a.name_data,NAMES,['src/data/ChineseSimplified/characters','src/data/ChineseSimplified/weapons','src/data/ChineseSimplified/artifacts','LICENSE'],t/'names')
        for must in [t/'source'/game,t/'resources/ExcelBinOutput/AvatarExcelConfigData.json',t/'resources/BinOutput',t/'names/src/data/ChineseSimplified/weapons',t/'names/src/data/ChineseSimplified/artifacts']:
            if not must.exists():raise ValueError('Incomplete upstream export: '+str(must))
        server.mkdir(exist_ok=True)
        for n in ('data','webstatic','lua'):(t/'source'/n).rename(server/n)
        (t/'resources').rename(server/'resources');(t/'source').rename(root/'source');(t/'names').rename(root/'name-data')
    print('Exported pinned static server inputs; no database/client supplied or modified.')
if __name__=='__main__':main()

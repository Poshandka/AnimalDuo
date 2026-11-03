#!/usr/bin/env python3
"""Index a player's existing IPA for one-time persistent resource installation.

Only metadata is written. Game data stays in the supplied IPA and on its drive.
The compact requirements file is shared by full installers and small updates.
"""
import argparse
import hashlib
import json
from pathlib import Path,PurePosixPath
import plistlib
import stat
import zipfile

PREFIX='Payload/DmIOS.app/'
ROOTS=('romfs/','msl/','aoc/','pso/','dm/font/')

def persistent(path):
    return path.startswith(ROOTS)

def safe(path):
    p=PurePosixPath(path)
    return bool(path) and not p.is_absolute() and not any(x in ('','.','..') for x in path.split('/')) and ':'not in path and not any(ord(x)<32 for x in path)

def index_ipa(ipa,output,title,version,chain,marker):
    if len(title)!=16 or any(c not in '0123456789ABCDEF'for c in title):raise ValueError('Expected the base title ID')
    files=[];directories=set()
    with zipfile.ZipFile(ipa)as z:
        names=set()
        for entry in z.infolist():
            if not entry.filename.startswith(PREFIX):continue
            path=entry.filename[len(PREFIX):].rstrip('/')
            if not persistent(path+'/') and not persistent(path):continue
            if not safe(path)or path in names or stat.S_ISLNK(entry.external_attr>>16):raise ValueError('Unsupported or duplicate resource path')
            names.add(path)
            if entry.is_dir():directories.add(path);continue
            digest=hashlib.sha256()
            with z.open(entry)as source:
                while data:=source.read(1<<20):digest.update(data)
            files.append({'path':path,'size':entry.file_size,'sha256':digest.hexdigest()})
            p=PurePosixPath(path).parent
            while str(p)!='.':
                if persistent(str(p)+'/'):directories.add(str(p))
                p=p.parent
    files.sort(key=lambda row:row['path']);directories=sorted(directories)
    if not files:raise ValueError('The IPA contains no persistent game resources')
    content={'title':title,'version':version,'chain':chain,'files':files,'directories':directories}
    identity=hashlib.sha256(json.dumps(content,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
    manifest=dict(content,id=identity,format=1)
    inventory=plistlib.dumps(manifest,fmt=plistlib.FMT_BINARY,sort_keys=True)
    checks=[];selected=set()
    by_path={x['path']:x for x in files}
    def check(row):
        if row['path']in selected:return
        selected.add(row['path']);checks.append({k:v for k,v in row.items()if k!='sha256'or row['size']<=4<<20})
    for root in ROOTS:
        choices=[row for row in files if row['path'].startswith(root)and row['size']<=4<<20]
        if choices:check(next((row for row in choices if row['size']),choices[0]))
    for path in ['dm/font/standard.ttf','romfs/'+marker]:
        if path in by_path:check(by_path[path])
    required_dirs=[root.rstrip('/')for root in ROOTS if any(row['path'].startswith(root)for row in files)]
    if 'romfs/'+marker in directories:required_dirs.append('romfs/'+marker)
    shader='msl/b-'+chain
    if shader not in directories:raise ValueError('The indexed shaders do not match the host chain')
    required_dirs.append(shader)
    requirements={'format':1,'id':identity,'title':title,'version':version,'chain':chain,'manifestSHA256':hashlib.sha256(inventory).hexdigest(),'manifestBytes':len(inventory),'files':len(files),'bytes':sum(row['size']for row in files),'checks':checks,'directories':sorted(set(required_dirs))}
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    (output/'resource-files.plist').write_bytes(inventory)
    (output/'resource-set.plist').write_bytes(plistlib.dumps(requirements,fmt=plistlib.FMT_BINARY,sort_keys=True))
    return requirements

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('ipa',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--title',required=True);p.add_argument('--version',required=True);p.add_argument('--chain',required=True);p.add_argument('--marker',required=True);a=p.parse_args()
    result=index_ipa(a.ipa,a.output,a.title,a.version,a.chain,a.marker)
    print(json.dumps({k:result[k]for k in ['id','files','bytes','manifestBytes']},indent=2))

if __name__=='__main__':main()

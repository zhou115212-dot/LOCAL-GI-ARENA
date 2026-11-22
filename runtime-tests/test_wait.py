"""Exercise the supervisor handoff with a harmless timer, never an actual game or server."""
from pathlib import Path
import os, subprocess, tempfile, time

ps = str(Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe')
snippet = Path(__file__).with_name('start-worker.txt').read_text(encoding='utf-8')
baseline = 'Start-Process -FilePath $shell -ArgumentList $a -WorkingDirectory $Root -WindowStyle Hidden -PassThru -RedirectStandardOutput "$Root\\logs\\supervisor.out.log" -RedirectStandardError "$Root\\logs\\supervisor.err.log" | Out-Null'
for mode, code in [('before', baseline), ('after', snippet)]:
    with tempfile.TemporaryDirectory(prefix='arena mock ') as tmp:
        root = Path(tmp)
        (root/'logs').mkdir()
        parent = """$ErrorActionPreference='Stop'
$Root=(Get-Location).Path
$shell=(Get-Process -Id $PID).Path
$a='-NoProfile -NonInteractive -Command "[Console]::WriteLine(''child output''); [Console]::Error.WriteLine(''child error''); Start-Sleep -Seconds 5; [IO.File]::WriteAllText(''done'',''ok'')"'
"""+code+"\n[Console]::WriteLine('READY')"
        proc = subprocess.Popen([ps,'-NoProfile','-NonInteractive','-Command',parent],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
        t=time.monotonic()
        rc=proc.wait(timeout=15)
        parent_s=time.monotonic()-t
        out,err=proc.communicate(timeout=16)
        eof_s=time.monotonic()-t
        finished=(root/'done').exists()
        deadline=time.monotonic()+12
        while not (root/'done').exists() and time.monotonic()<deadline:
            time.sleep(.1)
        time.sleep(.5)
        assert rc==0 and out.strip()==b'READY', (rc,out,err)
        assert (root/'done').exists(), 'worker failed'
        for log,marker in [('out','child output'),('err','child error')]:
            blob=(root/'logs'/('supervisor.'+log+'.log')).read_bytes().replace(b'\0',b'')
            assert marker.encode() in blob, log
        assert finished == (mode=='before'), (mode,finished)
        print(f'{mode}: parent exit {parent_s:.2f}s, output EOF {eof_s:.2f}s; worker finished at EOF={finished}; both logs OK')

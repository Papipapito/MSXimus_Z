# jpegerr.py <video.avi> — (MSXimus Z, 25/09/2026) clasifica cada "raya transitoria" de rayas.py: ¿el decodificador MJPEG dio ERROR en ese
# fotograma (artefacto de la capturadora/USB) o el fotograma decodifica limpio (glitch real en la imagen)?
import sys, subprocess, re, collections
vid = sys.argv[1]
# 1) rayas.py -> lista de fotogramas con raya
import os
here = os.path.dirname(os.path.abspath(__file__))
out = subprocess.run([sys.executable, os.path.join(here, 'rayas.py'), vid, os.path.splitext(vid)[0] + '_hits'], capture_output=True, text=True).stdout
hits = [int(m.group(1)) for m in re.finditer(r'^\s+f=\s*(\d+)', out, re.M)]
tot = re.search(r'rayas transitorias: (\d+)', out)
print('rayas transitorias:', tot.group(1) if tot else '?', ' fotogramas distintos:', len(set(hits)))
# 2) errores del decodificador por fotograma: showinfo numera los fotogramas y los errores mjpeg salen intercalados
p = subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'info', '-vsync', '0', '-i', vid, '-vf', 'showinfo', '-f', 'null', '-'],
                   capture_output=True, text=True, errors='replace').stderr
errs = collections.Counter(); n = -1
for line in p.splitlines():
    if 'showinfo' in line and ' n:' in line:
        m = re.search(r' n:\s*(\d+)', line)
        if m: n = int(m.group(1))
    elif '[mjpeg' in line and ('error' in line or 'invalid' in line or 'overread' in line or 'bad ' in line):
        errs[n + 1] += 1      # el error se imprime al decodificar el fotograma SIGUIENTE al ultimo mostrado
frames_err = set(errs)
print('fotogramas con error MJPEG:', len(frames_err), ' (total mensajes %d)' % sum(errs.values()))
con = [f for f in set(hits) if f in frames_err or (f - 1) in frames_err or (f + 1) in frames_err]
sin = [f for f in set(hits) if f not in con]
print('rayas EN fotogramas con error de decodificacion (+-1): %d   rayas en fotogramas LIMPIOS: %d' % (len(con), len(sin)))
print('  limpios:', sorted(sin)[:30])

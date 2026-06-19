#!/usr/bin/env python3
"""Convert a tmux `capture-pane -e` ANSI dump into a styled HTML <pre> for a clean
terminal screenshot (rendered to PNG via headless Chrome). Handles truecolor,
xterm-256, basic colors, bold and dim."""
import sys, html, re

BG = "#0c1016"        # terminal background (storm Midnat-ish)
FG = "#c9d3de"        # default foreground

# 16 base ANSI colors (xterm)
BASE16 = [
    "#1c2128", "#ff6b6b", "#5dd39e", "#f5b748", "#46b1ff", "#b98bff", "#56c8d8", "#c9d3de",
    "#67747f", "#ff8585", "#7fe0b6", "#ffcd6b", "#74c4ff", "#caa6ff", "#7fdce8", "#e8eef4",
]

def xterm256(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        levels = [0, 95, 135, 175, 215, 255]
        r, g, b = levels[(n // 36) % 6], levels[(n // 6) % 6], levels[n % 6]
        return f"#{r:02x}{g:02x}{b:02x}"
    v = 8 + (n - 232) * 10
    return f"#{v:02x}{v:02x}{v:02x}"

class St:
    def __init__(s): s.fg=None; s.bg=None; s.bold=False; s.dim=False
    def copy(s):
        t=St(); t.fg=s.fg; t.bg=s.bg; t.bold=s.bold; t.dim=s.dim; return t
    def style(s):
        p=[]
        fg=s.fg or FG
        if s.dim and s.fg is None: fg="#8b97a3"
        p.append(f"color:{fg}")
        if s.bg: p.append(f"background:{s.bg}")
        if s.bold: p.append("font-weight:700")
        if s.dim: p.append("opacity:.78")
        return ";".join(p)

def apply(st, params):
    i=0
    if not params: params=[0]
    while i < len(params):
        c=params[i]
        if c==0: st.fg=None; st.bg=None; st.bold=False; st.dim=False
        elif c==1: st.bold=True
        elif c==2: st.dim=True
        elif c==22: st.bold=False; st.dim=False
        elif 30<=c<=37: st.fg=BASE16[c-30]
        elif 90<=c<=97: st.fg=BASE16[c-90+8]
        elif 40<=c<=47: st.bg=BASE16[c-40]
        elif 100<=c<=107: st.bg=BASE16[c-100+8]
        elif c==39: st.fg=None
        elif c==49: st.bg=None
        elif c in (38,48):
            mode=params[i+1] if i+1<len(params) else 5
            if mode==5:
                col=xterm256(params[i+2]) if i+2<len(params) else FG
                i+=2
            elif mode==2:
                r,g,b=(params[i+2:i+5]+[0,0,0])[:3]
                col=f"#{r:02x}{g:02x}{b:02x}"; i+=4
            else: col=FG
            if c==38: st.fg=col
            else: st.bg=col
        i+=1
    return st

ANSI=re.compile(r"\x1b\[([0-9;]*)m")
text=open(sys.argv[1], encoding="utf-8", errors="replace").read()
# strip non-SGR escapes (cursor moves etc.)
text=re.sub(r"\x1b\][^\x07]*\x07","",text)
text=re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", lambda m: m.group(0) if m.group(0).endswith("m") else "", text)

st=St(); out=[]; pos=0
for m in ANSI.finditer(text):
    chunk=text[pos:m.start()]
    if chunk:
        out.append(f'<span style="{st.style()}">{html.escape(chunk)}</span>')
    params=[int(x) if x else 0 for x in m.group(1).split(";")] if m.group(1) else [0]
    st=apply(st, params); pos=m.end()
tail=text[pos:]
if tail: out.append(f'<span style="{st.style()}">{html.escape(tail)}</span>')

body="".join(out)
print(f'''<!doctype html><meta charset=utf-8><style>
*{{margin:0}} html,body{{background:{BG}}}
pre{{font:14px/1.34 "SF Mono","Menlo","Consolas",monospace;color:{FG};
  background:{BG};padding:20px 22px;white-space:pre;display:inline-block;
  letter-spacing:.1px;-webkit-font-smoothing:antialiased}}
</style><pre>{body}</pre>''')

import glob, os
S=os.path.dirname(os.path.abspath(__file__)); ART=os.path.join(S,'..','art')
BG='<rect x="0" y="0" width="250" height="350" fill="#fff"/>'
PAPER='#F4F1E9'; INK='#1D3BF0'
def body(svg): return svg[svg.index('>')+1:svg.rindex('</svg>')].replace(BG,'')
paper='''<filter id="paper" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="9" result="n"/>
<feColorMatrix in="n" type="matrix" values="0 0 0 0 0.5  0 0 0 0 0.47  0 0 0 0 0.4  0 0 0 0.20 0"/></filter>'''
paper_bg=f'<rect width="250" height="350" fill="{PAPER}"/><rect width="250" height="350" filter="url(#paper)"/>'
def ink_filter(fid, freq, cut, bleed=0, seed=3, dens=(0.6,0.62)):
    S_=14
    disp=(f'<feTurbulence type="fractalNoise" baseFrequency="0.05" numOctaves="3" seed="{seed+1}" result="w"/><feDisplacementMap in="SourceGraphic" in2="w" scale="{bleed}" xChannelSelector="R" yChannelSelector="G" result="src"/>' if bleed else '<feOffset in="SourceGraphic" result="src"/>')
    return f'''<filter id="{fid}" x="-5%" y="-5%" width="110%" height="110%">{disp}
<feTurbulence type="fractalNoise" baseFrequency="{freq}" numOctaves="1" seed="{seed}" result="n"/>
<feColorMatrix in="n" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 {S_} {-S_*cut}" result="m"/>
<feComposite in="src" in2="m" operator="in" result="sp"/>
<feTurbulence type="fractalNoise" baseFrequency="0.02" numOctaves="2" seed="{seed+7}" result="dn"/>
<feColorMatrix in="dn" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 {dens[0]} {dens[1]}" result="dm"/>
<feComposite in="sp" in2="dm" operator="in"/></filter>'''
def wrap(defs, content): return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 350"><defs>{paper}{defs}</defs>{paper_bg}{content}</svg>'
ink=lambda c,col=INK: c.replace('#0052FF',col)
g=lambda c,fid='f',op='',tr='',col=INK: f'<g filter="url(#{fid})" {op} {tr} style="mix-blend-mode:multiply">{ink(c,col)}</g>'
V=[
 ('Original (on chain today)', lambda c: f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 350">{BG}{c}</svg>'),
 ('1 · Riso: fine speckle, uneven ink', lambda c: wrap(ink_filter('f',1.4,0.36), g(c))),
 ('2 · Riso coarse grain', lambda c: wrap(ink_filter('f',0.6,0.36), g(c))),
 ('3 · Screenprint: bleed + grain', lambda c: wrap(ink_filter('f',1.2,0.34,bleed=2.6), g(c))),
 ('4 · Two-pass riso: offset ghost', lambda c: wrap(ink_filter('f',1.3,0.36)+ink_filter('h',0.8,0.42,seed=21), g(c,'h','opacity="0.32"','transform="translate(1.7,-1.3)"','#4A78FF')+g(c))),
]
files=sorted(glob.glob(os.path.join(ART,'shape-*.svg')))[10:16]
rows=''.join(f'<section><h2>{n}</h2><div class="r">'+''.join(f'<div class="c">{f(body(open(p).read()))}</div>' for p in files)+'</div></section>' for n,f in V)
thumbs=''.join(f'<div class="t"><h3>{n.split(" ·")[0]}</h3><div class="tr">'+''.join(f'<div class="tc">{f(body(open(p).read()))}</div>' for p in files[:5])+'</div></div>' for n,f in V)
zoom=''.join(f'<div class="z"><h3>{n}</h3>{f(body(open(files[1]).read()))}</div>' for n,f in V[1:])
html=f'''<!doctype html><meta charset="utf-8"><style>body{{margin:0;padding:28px;background:#e7e5df;font:14px/1.4 ui-monospace,Menlo,monospace;color:#222}}
h1{{font:700 26px system-ui;margin:0 0 6px}} h2{{font:600 14px ui-monospace;margin:22px 0 8px}} .r{{display:flex;gap:14px}} .c{{width:160px;height:224px;box-shadow:0 6px 18px rgba(0,0,0,.12)}} svg{{display:block;width:100%;height:100%}}
.zs{{display:grid;grid-template-columns:repeat(2,514px);gap:18px}} .z svg{{height:720px;box-shadow:0 6px 18px rgba(0,0,0,.12)}} h3{{font:600 12px ui-monospace;margin:0 0 6px}}
.tr{{display:flex;gap:6px}} .tc{{width:48px;height:67px;box-shadow:0 2px 6px rgba(0,0,0,.15)}} .ts{{display:flex;gap:28px;flex-wrap:wrap}}</style>
<h1>Shapes texture exploration, round 3</h1><div>Ink kept ~88% solid; texture from fine speckle, slow density variation, edge bleed and an offset second pass. Pure SVG filters.</div>
{rows}<h2>Thumbnail size (48 px)</h2><div class="ts">{thumbs}</div><h2>Detail</h2><div class="zs">{zoom}</div>'''
open(os.path.join(S,'textures3.html'),'w').write(html); print('ok')

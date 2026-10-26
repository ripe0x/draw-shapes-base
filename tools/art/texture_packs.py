import importlib.util, glob, os, re, sys
S=os.path.dirname(os.path.abspath(__file__)); OUT=sys.argv[1]
spec=importlib.util.spec_from_file_location('b3', os.path.join(S,'build3.py')); b3=importlib.util.module_from_spec(spec); spec.loader.exec_module(b3)
riso=b3.V[1][1]
for f in glob.glob(os.path.join(OUT,'svg','pack-*.svg')):
    s=open(f).read()
    # each card's Shape is a nested 250x350 svg: replace it with its riso version
    def sub(m):
        inner=m.group(0)
        out=riso(b3.body(inner))
        return out.replace('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 350">','<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 350" width="2000" height="2800">',1)
    n=0
    def rx(s):
        global n
        res=[];i=0
        tag='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 350"'
        while True:
            j=s.find(tag,i)
            if j<0: res.append(s[i:]); break
            k=s.find('</svg>',j)+6
            res.append(s[i:j]); res.append(sub(re.match(r'[\s\S]*',s[j:k]))); i=k
        return ''.join(res)
    s=rx(s).replace('fill="#fff" filter="url(#d)"', f'fill="{b3.PAPER}" filter="url(#d)"')
    open(f.replace('.svg','-riso.svg'),'w').write(s); os.remove(f)
print('ok')

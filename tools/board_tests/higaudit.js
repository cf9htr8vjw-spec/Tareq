// قياس HIG داخل الصفحة: أهداف اللمس، أصغر خط فعلي، الأوزان الرفيعة، التباين (WCAG) — يرجع ملخصاً وأسوأ الحالات
module.exports=async(page,opt)=>page.evaluate(opt=>{
  const vis=e=>{ const r=e.getBoundingClientRect(); if(r.width<1||r.height<1) return null; const cs=getComputedStyle(e); if(cs.visibility==='hidden'||cs.display==='none') return null;
    if(r.bottom<0||r.right<0||r.top>innerHeight*(opt.full?50:1)||r.left>innerWidth) return null;
    for(let p=e;p&&p!==document.documentElement;p=p.parentElement){ const s=getComputedStyle(p); if(s.display==='none'||s.visibility==='hidden'||+s.opacity===0) return null; }
    return r; };
  const scaleOf=e=>{ const r=e.getBoundingClientRect(); return e.offsetWidth?r.width/e.offsetWidth:1; };
  const P=c=>{ const m=c.match(/rgba?\(([^)]+)\)/); if(!m) return null; const a=m[1].split(/[ ,/]+/).filter(Boolean).map(Number); return [a[0],a[1],a[2],a.length>3?a[3]:1]; };
  const lum=([r,g,b])=>{ const f=v=>{ v/=255; return v<=.03928?v/12.92:Math.pow((v+.055)/1.055,2.4); }; return .2126*f(r)+.7152*f(g)+.0722*f(b); };
  const over=(fg,bg)=>[fg[0]*fg[3]+bg[0]*(1-fg[3]),fg[1]*fg[3]+bg[1]*(1-fg[3]),fg[2]*fg[3]+bg[2]*(1-fg[3]),1];
  const bgOf=e=>{ const stack=[]; let grad=false;
    for(let p=e;p;p=p.parentElement){ const s=getComputedStyle(p); if(s.backgroundImage&&s.backgroundImage!=='none'&&/gradient/.test(s.backgroundImage)){ const cs=[...s.backgroundImage.matchAll(/rgba?\([^)]+\)|#[0-9a-f]{3,6}/gi)].map(x=>x[0]); if(cs.length){ grad=true; let c=P(cs[0])||[255,255,255,1]; stack.push(c); if(c[3]>=.99) break; continue; } }
      const c=P(s.backgroundColor); if(c&&c[3]>0){ stack.push(c); if(c[3]>=.99) break; } }
    let bg=[255,255,255,1]; for(let i=stack.length-1;i>=0;i--) bg=over(stack[i],bg); return {bg,grad}; };
  const opa=e=>{ let o=1; for(let p=e;p;p=p.parentElement) o*=+getComputedStyle(p).opacity; return o; };
  const sel=e=>{ let s=e.tagName.toLowerCase(); if(e.id) s+='#'+e.id; else if(e.className&&typeof e.className==='string') s+='.'+e.className.trim().split(/\s+/).slice(0,2).join('.'); const p=e.parentElement; if(p&&!e.id){ s=(p.id?'#'+p.id:(p.className&&typeof p.className==='string'?'.'+p.className.trim().split(/\s+/)[0]:p.tagName.toLowerCase()))+' > '+s; } return s; };
  const out={text:[],small:[],thin:[],contrast:[],targets:[],targetsMin:[]};
  const RULES=[]; [...document.styleSheets].forEach(ss=>{ let rs; try{ rs=ss.cssRules; }catch(e){ return; } const walk=L=>[...L].forEach(r=>{ if(r.cssRules&&!r.selectorText){ if(!r.media||matchMedia(r.media.mediaText).matches) walk(r.cssRules); } else if(r.selectorText) RULES.push(r); }); walk(rs); });
  const ruleFor=(e,prop)=>{ let last=null; for(const r of RULES){ if(!r.style.getPropertyValue(prop)) continue; try{ if(e.matches(r.selectorText)) last=r.selectorText.slice(0,90)+' {'+prop+':'+r.style.getPropertyValue(prop)+'}'; }catch(x){} } if(last) return last; if(e.getAttribute('style')&&e.style.getPropertyValue(prop)) return 'inline style: '+(e.getAttribute('style')||'').slice(0,60); if(prop==='font-size'||prop==='color'){ for(let p=e.parentElement,k=0;p&&k<4;p=p.parentElement,k++){ for(const r of RULES){ if(!r.style.getPropertyValue(prop)) continue; try{ if(p.matches(r.selectorText)) last='↑'+r.selectorText.slice(0,80)+' {'+prop+':'+r.style.getPropertyValue(prop)+'}'; }catch(x){} } if(last) return last; if(p.getAttribute('style')&&p.style.getPropertyValue(prop)) return '↑inline: '+p.getAttribute('style').slice(0,60); } } return 'inherited'; };
  // النصوص
  const tw=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT); const seen=new Set();
  while(tw.nextNode()){ const t=tw.currentNode; if(!t.nodeValue.trim()) continue; const e=t.parentElement; if(!e||seen.has(e)) continue; seen.add(e);
    if(/^(SCRIPT|STYLE|NOSCRIPT|OPTION)$/.test(e.tagName)) continue; if(e.closest('.leaflet-control-attribution,svg')) continue;
    const r=vis(e); if(!r) continue; const cs=getComputedStyle(e); const fs=parseFloat(cs.fontSize)*scaleOf(e), fw=+cs.fontWeight||400;
    const txt=t.nodeValue.trim().slice(0,30);
    out.text.push(fs);
    if(fs<opt.minText-0.2) out.small.push({s:sel(e),fs:+fs.toFixed(1),t:txt,rule:opt.rules?ruleFor(e,'font-size'):''});
    if(fw<400&&fs<20) out.thin.push({s:sel(e),fw,fs:+fs.toFixed(1),t:txt});
    const fg=P(cs.color); if(!fg) continue; const {bg,grad}=bgOf(e); const f2=[fg[0],fg[1],fg[2],fg[3]*opa(e)]; const c=over(f2,bg);
    const L1=lum(c), L2=lum(bg), ratio=(Math.max(L1,L2)+.05)/(Math.min(L1,L2)+.05);
    const big=fs>=18||fw>=700, need=big?3:4.5; /* HIG: 18pt+ أو عريض بأي حجم ⇒ 3:1 */
    if(ratio<need) out.contrast.push({s:sel(e),r:+ratio.toFixed(2),need,fs:+fs.toFixed(1),fw,fg:cs.color,bg:`rgb(${bg.slice(0,3).map(Math.round)})`,grad,t:txt,rule:opt.rules?ruleFor(e,'color'):''}); }
  // أهداف اللمس/النقر
  document.querySelectorAll('button,a[href],input:not([type=hidden]),select,textarea,[role=button],[data-tab],[data-hm],[data-pm],label.tvUpDrop,label.rs,summary').forEach(e=>{
    const r=vis(e); if(!r) return; if(e.closest('.leaflet-control-attribution')) return; if(e.type==='file') return;
    let w=r.width,h=r.height; const pa=getComputedStyle(e,'::after'); if(pa.content&&pa.content!=='none'&&pa.position==='absolute'){ const sc=scaleOf(e), px=v=>parseFloat(v)||0; const ew=r.width-(px(pa.left)+px(pa.right))*sc, eh=r.height-(px(pa.top)+px(pa.bottom))*sc; if(ew>w) w=ew; if(eh>h) h=eh; }
    if(w<opt.tDef||h<opt.tDef) out.targets.push({s:sel(e),w:Math.round(w),h:Math.round(h),t:(e.innerText||e.value||e.getAttribute('aria-label')||'').trim().slice(0,20),cls:e.className&&typeof e.className==='string'?e.className:'',pos:getComputedStyle(e).position,af:getComputedStyle(e,'::after').content,bf:getComputedStyle(e,'::before').content,ov:getComputedStyle(e).overflow,rule:opt.rules?(()=>{ let best=null; for(const r of RULES){ try{ if(e.matches(r.selectorText)&&(r.style.getPropertyValue('padding')||r.style.getPropertyValue('height')||r.style.getPropertyValue('font-size'))) best=r.selectorText.slice(0,70); }catch(x){} } return best; })():''});
    if(w<opt.tMin||h<opt.tMin) out.targetsMin.push({s:sel(e),w:Math.round(w),h:Math.round(h)}); });
  const T=out.text.sort((a,b)=>a-b);
  const uniq=(a,k)=>{ const m=new Map(); a.forEach(x=>{ const key=k(x); if(!m.has(key)) m.set(key,Object.assign({n:0},x)); m.get(key).n++; }); return [...m.values()]; };
  return {texts:T.length,minText:+(T[0]||0).toFixed(1),small:uniq(out.small,x=>x.s+x.fs),thin:uniq(out.thin,x=>x.s),contrast:uniq(out.contrast,x=>x.s+x.r).sort((a,b)=>a.r-b.r),
    targets:uniq(out.targets,x=>x.s+x.w+'x'+x.h),targetsMin:uniq(out.targetsMin,x=>x.s+x.w+'x'+x.h),
    rm:[...document.styleSheets].some(ss=>{ try{ return [...ss.cssRules].some(r=>/prefers-reduced-motion/.test(r.conditionText||r.media&&r.media.mediaText||'')); }catch(e){ return false; } }),
    docW:document.documentElement.scrollWidth, vw:innerWidth};
},opt);

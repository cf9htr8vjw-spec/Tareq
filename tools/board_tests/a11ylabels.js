// أزرار بلا اسم مقروء (أيقونة/رمز فقط) — لـ VoiceOver
module.exports=async page=>page.evaluate(()=>{ const out=[];
  document.querySelectorAll('button,a[href],[role=button],input[type=button]').forEach(e=>{ const r=e.getBoundingClientRect(); if(r.width<1||r.height<1) return;
    const t=(e.innerText||'').replace(/[\s‏‎]/g,''); const hasWord=/[؀-ۿA-Za-z0-9]{2,}/.test(t);
    if(!hasWord&&!e.getAttribute('aria-label')&&!e.getAttribute('title')&&!e.querySelector('[aria-label]')) out.push((e.id?'#'+e.id:'')+(e.className&&typeof e.className==='string'?'.'+e.className.split(' ')[0]:'')+' «'+t.slice(0,6)+'»'); });
  return [...new Set(out)]; });

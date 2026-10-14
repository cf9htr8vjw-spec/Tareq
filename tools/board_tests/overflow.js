// reports any TV element whose content overflows its own box (clipped/spilling text)
module.exports=async(page)=>page.evaluate(()=>{
  const out=[];
  document.querySelectorAll('#tvPage1 .tvGauge *, #tvPage1 .tvTile, #tvPage1 .tvTile *, #tvPage1 .tvScope').forEach(el=>{
    const p=el.closest('.tvGauge,.tvTile,.tvScope'); if(!p) return;
    const r=el.getBoundingClientRect(), pr=p.getBoundingClientRect();
    if(r.width&&(r.left<pr.left-1||r.right>pr.right+1||r.bottom>pr.bottom+1)) out.push((p.className+' > '+el.className+' "'+(el.innerText||'').slice(0,30).replace(/\n/g,' ')+'"').trim());
  });
  return [...new Set(out)];
});

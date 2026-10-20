// قراءة جدول الإيرادات + ورقة «مفتاح المشاريع والمصادر» بنفس دالة الشاشة → JSON
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const fs=require('fs');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.route('**/rest/v1/**',r=>r.fulfill({status:404,contentType:'application/json',body:'{}'}));
  await p.goto('file:///home/user/Tareq/NHC_Live_Board.html',{waitUntil:'load'}); await p.waitForTimeout(500);
  const b64=fs.readFileSync(process.argv[2]).toString('base64');
  const out=await p.evaluate(async b64=>{ await loadSheetJS(); const bin=Uint8Array.from(atob(b64),c=>c.charCodeAt(0)); return tvRevParse(XLSX.read(bin,{type:'array'})); },b64);
  fs.writeFileSync(process.argv[3],JSON.stringify({rows:out.rows,meta:out.meta}));
  const pj=out.rows.filter(r=>!r.is_region), reg=out.rows.filter(r=>r.is_region), S=(a,k)=>a.reduce((x,r)=>x+(+r[k]||0),0);
  console.log('collAsOf',out.collAsOf,'| meta',JSON.stringify(out.meta));
  console.log('key',JSON.stringify(out.key));
  console.log('projects',pj.length,'with codes',pj.filter(r=>r.alloc_codes).length,'excluded',pj.filter(r=>r.excluded).map(r=>r.name).join('،'),'| noFin',pj.filter(r=>r.alloc_codes&&!r.fin_code).length);
  console.log('regions target_year',(S(reg,'target_year')/1e6).toFixed(2),'| projects target_year',(S(pj,'target_year')/1e6).toFixed(2),'| target_cum_y',(S(reg,'target_cum_y')/1e6).toFixed(2));
  console.log('y_cash_pct sample',pj.slice(0,4).map(r=>r.name+':'+(r.y_cash_pct==null?'-':r.y_cash_pct.toFixed(3))).join(' · '));
  console.log('ERR',errs);
  await b.close();
})();

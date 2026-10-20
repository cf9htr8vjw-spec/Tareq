const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const fs=require('fs');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.route('**/rest/v1/**',r=>r.fulfill({status:404,contentType:'application/json',body:'{}'}));
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html?tv=1',{waitUntil:'load'}); await p.waitForTimeout(500);
  const b64=fs.readFileSync(process.argv[2]).toString('base64');
  const out=await p.evaluate(async b64=>{ await loadSheetJS(); const bin=Uint8Array.from(atob(b64),c=>c.charCodeAt(0)); return tvRevParse(XLSX.read(bin,{type:'array'})); },b64);
  fs.writeFileSync('/tmp/pwtest/revparams.json',JSON.stringify(out.rows));
  console.log('sheet',out.sheet,'asOf',out.asOf,'rows',out.rows.length,'regions',out.rows.filter(r=>r.is_region).map(r=>r.name+':'+r.sector).join(', '));
  console.log(out.rows.filter(r=>!r.is_region).slice(0,6).map(r=>`${r.name}|${r.sector}|ex=${r.excluded}|pct=${r.cash_pct&&r.cash_pct.toFixed(3)}`).join('\n'));
  console.log('ERR',errs);
  await b.close();
})();

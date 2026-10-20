const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const fs=require('fs');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message)); await p.route('**/rest/v1/**',r=>r.fulfill({status:404,body:'{}'}));
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html?tv=1'); await p.waitForTimeout(400);
  const b64=fs.readFileSync(process.argv[2]).toString('base64');
  const out=await p.evaluate(async b64=>{ await loadSheetJS(); const bin=Uint8Array.from(atob(b64),c=>c.charCodeAt(0)); const r=tvBankPolicyParse(XLSX.read(bin,{type:'array'}));
    return {r, flat:[0.0496,0.039,0.0468].map(x=>[x,tvFlatRate(x,20)]), keys:["مصرف الراجحي","البنك الأهلي السعودي","الأهلي - التمويل البديل","البنك العربي الوطني","بنك الإنماء","البنك السعودي الأول","البنك السعودي الفرنسي","بنك الرياض","البنك السعودي للاستثمار","بنك البلاد","بنك الجزيرة","نقدي"].map(n=>n+'→'+tvBankKey(n))}; },b64);
  fs.writeFileSync(process.argv[3],JSON.stringify(out.r));
  console.log('month',out.r.month,'rows',out.r.rows.length);
  out.r.rows.forEach(x=>{ const d=x.data; console.log(x.bank,'|',d.name,'| rates',JSON.stringify(d.rates),'| init',Object.entries(d.init||{}).filter(([k,v])=>v===true).map(([k])=>k).join(','),'| term',d.pol&&d.pol.term,'| age',d.pol&&d.pol.age,'| sal gov',d.pol&&d.pol.sal.gov_t); });
  console.log('flat',JSON.stringify(out.flat)); console.log(out.keys.join(' · ')); console.log('ERR',errs);
  await b.close();
})();

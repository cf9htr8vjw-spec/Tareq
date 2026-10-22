// رفع ملف «أسعار صفقات السوق» من الشاشة: التعرّف التلقائي (ملف كبير بأوراق أسبوعية)، الملخص، صفوف الرفع. الاستعمال: node mktup.js <xlsx>
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const GW=require('/tmp/pwtest/gw.js');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage({viewport:{width:1366,height:768}}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  const calls=[];
  await p.route('**/rest/v1/**',GW(async(route,__url,__post)=>{
    const m=__url.match(/rpc\/([a-z_0-9]+)/); const fn=m&&m[1]; let body=null; const q=JSON.parse(__post||'{}');
    if(fn==='admin_load_tv_market'){ calls.push(q); body={ok:true,count:q.p_rows.length,msg:'ok'}; }
    else if(fn==='admin_sessions') body={ok:true,sessions:[]};
    else if(fn==='get_app_state') body={ok:true,enabled:true};
    else if(fn==='get_live_board') body={ok:true,empty:true};
    if(body===null) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"mock"}'});
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
  }));
  await GW.init(p);
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html?tv=1&page=4',{waitUntil:'load'}); await p.waitForTimeout(1000);
  await p.keyboard.press('u'); await p.waitForTimeout(200);
  const t0=Date.now();
  await p.setInputFiles('#tvUpFile',process.argv[2]); await p.waitForFunction(()=>/أسبوع|تعذّر|لم أ/.test(document.getElementById('tvUpMsg').innerText),null,{timeout:600000});
  console.log('read ms:',Date.now()-t0);
  console.log('summary:',(await p.evaluate(()=>document.getElementById('tvUpMsg').innerText)).replace(/\n/g,' | '));
  console.log('go label:',await p.evaluate(()=>document.getElementById('tvUpGo').textContent));
  await p.fill('#tvUpUser','tareq'); await p.fill('#tvUpPass','pw'); await p.click('#tvUpGo'); await p.waitForTimeout(1500);
  console.log('result:',await p.evaluate(()=>document.getElementById('tvUpMsg').innerText));
  const rows=calls.flatMap(c=>c.p_rows); const byWk={}; rows.forEach(r=>{ const k=r.wk; byWk[k]=byWk[k]||{deals:0,value:0,ex:0,n:0}; byWk[k].deals+=r.deals; byWk[k].value+=r.value; byWk[k].ex+=r.excluded; byWk[k].n++; });
  console.log('weeks:',JSON.stringify(byWk)); console.log('sample:',JSON.stringify(rows.find(r=>r.city==='جدة'&&r.type==='شقة')));
  console.log('PAGE ERRORS:',errs.length,errs.join(' | ')); await b.close();
})();

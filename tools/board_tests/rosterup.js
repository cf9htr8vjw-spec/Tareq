// رفع ملف «بيانات الموظفين» من الشاشة: التعرّف التلقائي، الملخص، وأن المرفوع بلا هوية/بريد/جوال. الاستعمال: node rosterup.js <xlsx>
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage({viewport:{width:1920,height:1080}}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  const calls=[];
  await p.route('**/rest/v1/**',async route=>{
    const url=route.request().url(); const m=url.match(/rpc\/([a-z_]+)/); let body=null; const q=JSON.parse(route.request().postData()||'{}');
    if(m){ const fn=m[1]; if(/^admin_|^login$/.test(fn)) calls.push({fn,q});
      if(fn==='login') body={ok:true,admin:true,name:'طارق'};
      else if(fn==='admin_load_tv_ops') body={ok:true,count:q.p_rows.length,msg:'ok'};
      else if(fn==='get_live_board') body={ok:true,empty:true};
      else body=fn==='get_dashboard_targets'?{ok:true,scopes:{}}:[]; }
    else body=[];
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
  });
  await p.goto('file:///home/user/Tareq/NHC_Live_Board.html?page=3',{waitUntil:'load'}); await p.waitForTimeout(1000);
  await p.keyboard.press('u'); await p.waitForTimeout(200);
  await p.setInputFiles('#tvUpFile',process.argv[2]); await p.waitForFunction(()=>/اسماً|تعذّر|لم أ/.test(document.getElementById('tvUpMsg').innerText),null,{timeout:120000});
  console.log('summary:',await p.evaluate(()=>document.getElementById('tvUpMsg').innerText.replace(/\n/g,' | ')));
  console.log('go label:',await p.evaluate(()=>document.getElementById('tvUpGo').textContent));
  await p.fill('#tvUpUser','tareq'); await p.fill('#tvUpPass','pw'); await p.click('#tvUpGo'); await p.waitForTimeout(1200);
  console.log('result:',await p.evaluate(()=>document.getElementById('tvUpMsg').innerText));
  const up=calls.find(c=>c.fn==='admin_load_tv_ops');
  if(up){ const txt=JSON.stringify(up.q.p_rows); console.log('table:',up.q.p_table,'reset:',up.q.p_reset,'rows:',up.q.p_rows.length,'keys:',Object.keys(up.q.p_rows[0]).join(','),
    '| has 10-digit:',/\d{10}/.test(txt),'| has @:',/@/.test(txt)); }
  console.log('PAGE ERRORS:',errs.length,errs.join(' | ')); await b.close();
})();

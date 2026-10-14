const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:1920,height:1080}});
  const errs=[]; page.on('pageerror',e=>errs.push(e.message));
  let inserts=[], liveCalls=0, logins=[];
  await page.route('**/rest/v1/**',async route=>{
    const url=route.request().url(); const m=url.match(/rpc\/([a-z_]+)/); let body=null;
    const q=JSON.parse(route.request().postData()||'{}');
    if(m){ const fn=m[1];
      if(fn==='login'){ logins.push(q.p_user); body = q.p_pass!=='good' ? {ok:false,msg:'بيانات دخول غير صحيحة'} : (q.p_user==='sales4'?{ok:true,admin:false,name:'مندوب'}:{ok:true,admin:true,name:'طارق'}); }
      else if(fn==='admin_insert_live_snapshot'){ inserts.push(q); body={ok:true,count:q.p_rows.length,msg:'ok'}; }
      else if(fn==='get_live_board'){ liveCalls++; body={ok:true,empty:true}; }
      else body=fn==='get_dashboard_targets'?{ok:true,scopes:{}}:[];
    } else body=[];
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
  });
  await page.goto('file:///home/user/Tareq/NHC_Live_Board.html?page=1',{waitUntil:'load'});
  await page.waitForTimeout(1200);
  const vis=async()=>page.evaluate(()=>getComputedStyle(document.getElementById('tvUpBtn')).opacity);
  console.log('button opacity before mouse:',await vis());
  await page.mouse.move(400,400); await page.mouse.move(420,420); await page.waitForTimeout(400);
  console.log('button opacity after mouse:',await vis());
  await page.click('#tvUpBtn');
  console.log('modal open:',await page.evaluate(()=>document.getElementById('tvUpModal').classList.contains('on')));
  await page.setInputFiles('#tvUpFile','/tmp/pwtest/up/data_21.xlsx');
  await page.waitForTimeout(1500);
  console.log('summary:',await page.evaluate(()=>document.getElementById('tvUpMsg').innerText));
  console.log('go disabled w/o creds:',await page.evaluate(()=>document.getElementById('tvUpGo').disabled));
  // wrong password
  await page.fill('#tvUpUser','tareq'); await page.fill('#tvUpPass','bad'); await page.click('#tvUpGo'); await page.waitForTimeout(500);
  console.log('wrong pass ->',await page.evaluate(()=>document.getElementById('tvUpMsg').innerText),'| inserts:',inserts.length);
  // non-admin
  await page.fill('#tvUpUser','sales4'); await page.fill('#tvUpPass','good'); await page.click('#tvUpGo'); await page.waitForTimeout(500);
  console.log('non-admin ->',await page.evaluate(()=>document.getElementById('tvUpMsg').innerText),'| inserts:',inserts.length);
  // admin
  await page.fill('#tvUpUser','tareq'); await page.fill('#tvUpPass','good');
  await page.screenshot({path:'/tmp/pwtest/tv_upload_modal.png'});
  const liveBefore=liveCalls;
  await page.click('#tvUpGo'); await page.waitForTimeout(1200);
  console.log('admin ->',await page.evaluate(()=>document.getElementById('tvUpMsg').innerText));
  const rows=inserts.flatMap(x=>x.p_rows);
  console.log('insert calls:',inserts.length,'rows:',rows.length,'contracts:',rows.reduce((s,r)=>s+r.contracts_total,0),'nhc:',rows.filter(r=>r.is_nhc).reduce((s,r)=>s+r.contracts_total,0),'bookings:',rows.reduce((s,r)=>s+r.bookings,0),'admin sent:',inserts[0]&&inserts[0].p_admin,'same batch:',new Set(inserts.map(x=>x.p_batch_id)).size===1,'snapshot_at:',inserts[0]&&inserts[0].p_snapshot_at);
  console.log('dashboard reloaded after upload:',liveCalls>liveBefore);
  await page.waitForTimeout(1800);
  console.log('modal closed:',!(await page.evaluate(()=>document.getElementById('tvUpModal').classList.contains('on'))));
  // second upload: creds remembered
  await page.keyboard.press('u'); await page.waitForTimeout(200);
  console.log('2nd open via U, auth hidden:',await page.evaluate(()=>getComputedStyle(document.getElementById('tvUpAuth')).display==='none'),'| who:',await page.evaluate(()=>document.getElementById('tvUpWho').innerText));
  console.log('localStorage keys w/ pass:',await page.evaluate(()=>Object.keys(localStorage).filter(k=>/(pass|cred)/i.test(k)||String(localStorage.getItem(k)).includes('good'))));
  console.log('PAGE ERRORS:',errs.length,errs.join(' | '));
  await browser.close();
})();

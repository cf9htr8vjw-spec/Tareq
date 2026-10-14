const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:1920,height:1080}});
  const errs=[]; page.on('pageerror',e=>errs.push(e.message));
  let inserts=[], deletes=[], deleted=false;
  const LIVE={ok:true,empty:false,day:new Date().toISOString().slice(0,10),latest_at:'2026-10-12T08:10:00Z',prev_at:'2026-10-12T07:56:00Z',first_at:'2026-10-12T06:06:00Z',snapshots_today:4,
    latest:{all:{contracts:154965,bookings:5568},nhc:{contracts:28066},dev:{contracts:126899}},prev:{all:{contracts:1}},first:{all:{contracts:1}},timeline:[{at:'2026-10-12T06:06:00Z',contracts:1,nhc:0},{at:'2026-10-12T07:16:00Z',contracts:1,nhc:0},{at:'2026-10-12T07:56:00Z',contracts:1,nhc:0},{at:'2026-10-12T08:10:00Z',contracts:154965,nhc:28066},{at:'2026-10-12T08:27:00Z',contracts:2,nhc:2}],movers:[],feed:[],today_by_sector:{}};
  await page.route('**/rest/v1/**',async route=>{
    const url=route.request().url(); const m=url.match(/rpc\/([a-z_]+)/); let body=null;
    const q=JSON.parse(route.request().postData()||'{}');
    if(m){ const fn=m[1];
      if(fn==='login') body= q.p_pass==='good'?{ok:true,admin:true,name:'طارق'}:{ok:false,msg:'بيانات دخول غير صحيحة'};
      else if(fn==='admin_insert_live_snapshot'){ inserts.push(q); body={ok:true,count:q.p_rows.length}; }
      else if(fn==='admin_delete_live_snapshot'){ deletes.push(q); deleted=true; body={ok:true,count:788}; }
      else if(fn==='get_live_board') body= deleted?{ok:true,empty:true}:LIVE;
      else body=fn==='get_dashboard_targets'?{ok:true,scopes:{}}:[];
    } else body=[];
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
  });
  page.on('console',m=>{ if(m.type()==='error') console.log('CONSOLE:',m.text()); });
  page.on('dialog',d=>{ console.log('confirm text:',d.message()); d.accept(); });
  await page.goto('file:///home/user/Tareq/NHC_Live_Board.html?page=1',{waitUntil:'load'}); await page.waitForTimeout(1200);
  console.log('early errs:',errs.join(' | ')); await page.keyboard.press('u'); await page.waitForTimeout(200);
  console.log('pulls:',await page.evaluate(()=>[...document.querySelectorAll('.tvUpPull')].map(r=>(r.classList.contains('bad')?'[BAD] ':'')+r.innerText.replace(/\n+/g,' ')).join(' || ')));
  await page.setInputFiles('#tvUpFile','/tmp/pwtest/up2/cumulative.xlsx'); await page.waitForTimeout(1500);
  await page.fill('#tvUpUser','tareq'); await page.fill('#tvUpPass','good');
  console.log('warning:',await page.evaluate(()=>document.getElementById('tvUpMsg').innerText));
  console.log('go disabled before confirm:',await page.evaluate(()=>document.getElementById('tvUpGo').disabled),'| confirm visible:',await page.evaluate(()=>getComputedStyle(document.getElementById('tvUpConfirmRow')).display));
  await page.screenshot({path:process.env.OUT});
  await page.check('#tvUpConfirm');
  console.log('go disabled after confirm:',await page.evaluate(()=>document.getElementById('tvUpGo').disabled));
  await page.uncheck('#tvUpConfirm');
  // undo
  await page.click('.tvUpPull.bad button'); await page.waitForTimeout(1000);
  console.log('delete calls:',deletes.length,'at:',deletes[0]&&deletes[0].p_snapshot_at,'user:',deletes[0]&&deletes[0].p_admin,'| msg:',await page.evaluate(()=>document.getElementById('tvUpMsg').innerText));
  console.log('pulls after delete visible:',await page.evaluate(()=>getComputedStyle(document.getElementById('tvUpPulls')).display));
  // normal file: no warning
  await page.setInputFiles('#tvUpFile','/tmp/pwtest/up/data_21.xlsx'); await page.waitForTimeout(1500);
  console.log('normal file go disabled:',await page.evaluate(()=>document.getElementById('tvUpGo').disabled),'| confirm visible:',await page.evaluate(()=>getComputedStyle(document.getElementById('tvUpConfirmRow')).display),'| inserts so far:',inserts.length);
  console.log('PAGE ERRORS:',errs.length,errs.join(' | '));
  await browser.close();
})();

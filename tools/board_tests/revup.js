const GW=require('/tmp/pwtest/gw.js');
// رفع جدول الإيرادات من الشاشة: رسالة الملخص (ورقة المفتاح) ووصول p_meta والأكواد للقاعدة، والرجوع للدالة القديمة
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage({viewport:{width:1920,height:1080}}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  let sent=null, calls=0;
  await p.route('**/rest/v1/**',GW(async(r,__url,__post)=>{ const m=__url.match(/rpc\/([a-z_]+)/); const q=JSON.parse(__post||'{}');
    if(m&&m[1]==='admin_sessions') return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify({ok:true,admin:true,name:'طارق'})});
    if(m&&m[1]==='admin_load_tv_rev'){ calls++; if(process.env.OLDFN&&'p_meta' in q) return r.fulfill({status:404,contentType:'application/json',body:'{"message":"Could not find the function public.admin_load_tv_rev(p_admin, p_meta, p_pass, p_rows)"}'});
      sent=q; return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify({ok:true,count:q.p_rows.length})}); }
    return r.fulfill({status:404,contentType:'application/json',body:'{}'}); }));
  await GW.init(p);
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html?tv=1',{waitUntil:'load'}); await p.waitForTimeout(800);
  await p.evaluate(()=>tvUpOpen());
  await p.setInputFiles('#tvUpFile',process.argv[2]); await p.waitForTimeout(2500);
  console.log('MSG:',(await p.textContent('#tvUpMsg')).replace(/\s+/g,' ').slice(0,900));
  await p.fill('#tvUpUser','tareq'); await p.fill('#tvUpPass','pw'); await p.waitForTimeout(200);
  const conf=await p.$('#tvUpConfirm'); if(conf&&await conf.isVisible()) await conf.check();
  await p.evaluate(()=>tvUpGoRev()); await p.waitForTimeout(1500);
  console.log('calls',calls,'| sent meta:',sent&&JSON.stringify(sent.p_meta||null).slice(0,160),'| rows with codes:',sent&&sent.p_rows.filter(r=>r.alloc_codes).length,'| has new cols:',sent&&('y_cash_pct' in (sent.p_rows.find(r=>!r.is_region&&r.y_value)||{})));
  console.log('AFTER:',(await p.textContent('#tvUpMsg')).replace(/\s+/g,' ').slice(0,260));
  console.log('ERR',errs);
  await b.close();
})();

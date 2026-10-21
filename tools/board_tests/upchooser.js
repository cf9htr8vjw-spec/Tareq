// الرفع من «العرض الشامل» المفتوح من الخيار بعد الدخول (الرابط العادي بلا ?tv=1): الزر يفتح النافذة، وحساب الأدمن
// الذي دخل بكلمة مروره لا يُطلب منه إدخالها مرة ثانية، والرفع يمرّ. الاستعمال: node upchooser.js <xlsx>
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const GW=require('/tmp/pwtest/gw.js');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage({viewport:{width:1366,height:768}}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  const calls=[];
  process.env.NOSESS='1';
  await p.route('**/rest/v1/**',GW(async(route,__url,__post)=>{
    const m=__url.match(/rpc\/([a-z_0-9]+)/); const fn=m&&m[1]; let body=null; const q=JSON.parse(__post||'{}');
    if(fn&&/^admin_/.test(fn)) calls.push({fn,admin:q.p_admin,hasPass:!!q.p_pass});
    if(fn==='get_app_state') body={ok:true,enabled:true};
    else if(fn==='get_live_board') body={ok:true,empty:true};
    else if(fn==='admin_load_tv_ops') body={ok:true,count:(q.p_rows||[]).length,msg:'ok'};
    else if(fn&&/^admin_/.test(fn)) body={ok:true,count:(q.p_rows||[]).length,msg:'ok'};
    if(body===null) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"mock"}'});
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
  }));
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html',{waitUntil:'load'}); await p.waitForTimeout(800);
  await GW.login(p,'tareq','good'); await p.waitForTimeout(400);
  await p.click('.chOpt[data-ch="board"]'); await p.waitForTimeout(1500);
  await p.mouse.move(300,300); await p.mouse.move(320,320); await p.waitForTimeout(300);
  await p.click('#tvUpBtn');
  console.log('modal opens from chooser board:',await p.evaluate(()=>document.getElementById('tvUpModal').classList.contains('on')));
  if(process.argv[2]){
    await p.setInputFiles('#tvUpFile',process.argv[2]);
    await p.waitForFunction(()=>/اسماً|ملف التخصيص|تعذّر|لم أ|مشروعاً/.test(document.getElementById('tvUpMsg').innerText),null,{timeout:120000});
    console.log('summary:',(await p.evaluate(()=>document.getElementById('tvUpMsg').innerText)).replace(/\n/g,' | ').slice(0,160));
    console.log('auth fields hidden (admin pass in memory):',await p.evaluate(()=>getComputedStyle(document.getElementById('tvUpAuth')).display==='none'),'| go enabled:',await p.evaluate(()=>!document.getElementById('tvUpGo').disabled));
    await p.click('#tvUpGo'); await p.waitForTimeout(2500);
    console.log('result:',(await p.evaluate(()=>document.getElementById('tvUpMsg').innerText)).slice(0,160));
    console.log('admin calls:',[...new Set(calls.map(c=>c.fn+'('+c.admin+','+(c.hasPass?'pass':'NOPASS')+')'))].join(' '));
  }
  /* «U» من «التفاصيل» لا يفتح نافذة الشاشة */
  await p.keyboard.press('Escape'); await p.evaluate(()=>{ uiMode="app"; }); await p.waitForTimeout(300); await p.keyboard.press('u'); await p.waitForTimeout(200);
  console.log('U in details opens modal:',await p.evaluate(()=>document.getElementById('tvUpModal').classList.contains('on')));
  console.log('PAGE ERRORS:',errs.length,errs.join(' | ')); await b.close();
})();

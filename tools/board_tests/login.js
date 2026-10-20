// الدخول الموحّد (app_security.sql): شاشة الدخول لكل الأجهزة، خيار «العرض الشامل / التفاصيل»، استعادة الجلسة، الخروج،
// جلسة شاشة العرض (بلا تفاصيل)، وإخفاء المالي لمن لا يملك صلاحيته. يُشغَّل على 1366×768 و390×844 (MOBILE=1).
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const GW=require('/tmp/pwtest/gw.js');
const BASE='file:///home/user/Tareq/SalesPlace_01.html';
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const ctx=await browser.newContext({viewport:{width:+(process.env.VW||1366),height:+(process.env.VH||768)},isMobile:!!process.env.MOBILE,hasTouch:!!process.env.MOBILE});
  const page=await ctx.newPage(); const errs=[]; page.on('pageerror',e=>errs.push(e.message));
  const direct=[];
  await page.route('**/rest/v1/**',GW(async(route,__url,__post)=>{
    const m=__url.match(/rpc\/([a-z_0-9]+)/); const fn=m&&m[1];
    { const real=(route.request().url().match(/rpc\/([a-z_0-9]+)/)||[])[1]; if(real&&!/^api$|^api_read$|^login_v2$|^get_app_state$/.test(real)) direct.push(real); }
    let body=null;
    if(fn==='get_app_state') body={ok:true,enabled:true,message:''};
    else if(fn==='get_live_board') body={ok:true,empty:true};
    else if(fn==='get_dashboard_targets') body={ok:true,year:2026,scopes:{nhc:{total:14081,projects:32,by_sector:{},rev_total:2570870060},dev:{total:70645,projects:178,by_sector:{}}}};
    else if(fn==='get_tv_ops') body={ok:true,has_channel:true,has_emp:true,has_fin:true,has_roster:false,bucket:'day',series:[],channels:[],employees:[],banks:[],kpi:{n:5,vn:5,ben:3,cash:1,prev:2},book:{},dims:{dests:[{v:'خزام',n:3}],projects:[{v:'خزام بارك',dest:'خزام',n:3}],channels:['مركز بيع']},policy:[]};
    if(body===null) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"mock"}'});
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
  }));
  const vis=sel=>page.evaluate(s=>{ const e=document.querySelector(s); if(!e) return 'none'; const cs=getComputedStyle(e); return cs.display!=='none'&&cs.visibility!=='hidden'&&!e.classList.contains('hide')&&(e.offsetWidth>0||e.offsetHeight>0); },sel);
  /* 1. بلا جلسة: شاشة الدخول للتطبيق ولشاشة العرض */
  process.env.NOSESS='1';
  await page.goto(BASE,{waitUntil:'load'}); await page.waitForTimeout(900);
  console.log('lock visible:',await vis('#lock'),'| app hidden:',!(await vis('#app')),'| title:',await page.textContent('#lock h2'));
  await GW.login(page,'tareq','wrong'); console.log('wrong pass:',await page.textContent('#lockMsg'));
  await GW.login(page,'tareq','good'); await page.waitForTimeout(500);
  console.log('after login → chooser:',await vis('#chooser'),'| who:',await page.textContent('#chWho'),'| kind:',GW.logins.map(l=>l.p_kind).join(','));
  await page.click('.chOpt[data-ch="app"]'); await page.waitForTimeout(300);
  console.log('details without catalog key → toast, chooser still:',await vis('#chooser'));
  await page.click('.chOpt[data-ch="board"]'); await page.waitForTimeout(1200);
  console.log('board on:',await vis('#tvView'),'| mode saved:',await page.evaluate(()=>sessionStorage.getItem('nhc_mode')),'| session stored:',await page.evaluate(()=>!!sessionStorage.getItem('nhc_session')),'| localStorage has session:',await page.evaluate(()=>!!localStorage.getItem('nhc_session')));
  console.log('direct (non-gateway) calls:',[...new Set(direct)].join(',')||'none');
  /* 2. إعادة التحميل تستعيد الجلسة بلا دخول */
  await page.reload({waitUntil:'load'}); await page.waitForTimeout(1200);
  console.log('after reload → board:',await vis('#tvView'),'lock:',await vis('#lock'));
  /* 3. الخروج */
  await page.evaluate(()=>doLogout()); await page.waitForTimeout(1200);
  console.log('after logout → lock:',await vis('#lock'),'| session cleared:',await page.evaluate(()=>!sessionStorage.getItem('nhc_session')));
  /* 4. شاشة العرض ?tv=1: دخول ثم الشاشة مباشرة، جلسة tv على الشاشة الكبيرة */
  GW.logins.length=0;
  await page.goto(BASE+'?tv=1',{waitUntil:'load'}); await page.waitForTimeout(900);
  console.log('tv: lock first:',await vis('#lock'),'| note:',(await page.textContent('#lockNote')).slice(0,40));
  await GW.login(page,'tareq','good'); await page.waitForTimeout(1500);
  console.log('tv: board:',await vis('#tvView'),'| chooser:',await vis('#chooser'),'| kind sent:',GW.logins[0]&&GW.logins[0].p_kind,'| stored in localStorage:',await page.evaluate(()=>!!localStorage.getItem('nhc_session')),'| details btn hidden:',!(await vis('#tvAppBtn')));
  await page.evaluate(()=>doLogout()); await page.waitForTimeout(800);
  console.log('PAGE ERRORS:',errs.length,errs.join(' | '));
  await browser.close();
})();

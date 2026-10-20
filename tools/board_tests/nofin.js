// مستخدم بلا صلاحية مالية (NOFIN=1 عبر gw.js): لا زر إيرادات، لا شريط «قيمة العقود»، متوسط قيمة العقد «—»، والبطاقة المالية مخفية
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const GW=require('/tmp/pwtest/gw.js');
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:1366,height:768}}); const errs=[]; page.on('pageerror',e=>errs.push(e.message));
  await page.route('**/rest/v1/**',GW(async(route,__url,__post)=>{
    const m=__url.match(/rpc\/([a-z_0-9]+)/); const fn=m&&m[1]; let body=null;
    if(fn==='get_app_state') body={ok:true,enabled:true};
    else if(fn==='get_live_board') body={ok:true,empty:true};
    else if(fn==='get_tv_ops') body={ok:true,has_channel:true,has_emp:true,has_fin:true,has_roster:false,bucket:'day',series:[],channels:[{ch:'مركز بيع',n:5,prev:2}],employees:[{e:'سارة',w:'الوسطى',n:5,ch:'مركز بيع',prev:1}],banks:[{b:'الراجحي',n:4,rs:0.2,rn:4,ts:80,tn:4,fs:0.1,fn:4,prev:1}],kpi:{n:5,vn:5,ben:3,cash:1,prev:2,fan:4,saln:4},book:{},dims:{dests:[],projects:[],channels:['مركز بيع']},policy:[]};   /* vs/fa/sal محذوفة كما تفعل البوابة */
    if(body===null) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"mock"}'});
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
  }));
  await GW.init(page);
  await page.goto('file:///home/user/Tareq/SalesPlace_01.html?tv=1&page=3',{waitUntil:'load'}); await page.waitForTimeout(1500);
  const vis=sel=>page.evaluate(s=>{ const e=document.querySelector(s); return !!e&&getComputedStyle(e).display!=='none'; },sel);
  console.log('FIN:',await page.evaluate(()=>FIN),'| rev seg hidden:',!(await vis('#tvMetricSeg')),'| price band btn hidden:',!(await vis('#tvBandSeg button[data-v="price"]')));
  console.log('kpi avg value:',await page.evaluate(()=>[...document.querySelectorAll('#tvOpsKpis .k')].find(k=>/متوسط قيمة العقد/.test(k.innerText)).innerText.replace(/\n/g,' | ')));
  console.log('fin strip present:',await page.evaluate(()=>!!document.querySelector('#tvOpsEmp .tvOpsFinS')),'| bank fa cell:',await page.evaluate(()=>{ const r=document.querySelector('#tvOpsBanks .tvOpsB:not(.h)'); return r?r.children[10].innerText:'-'; }));
  await page.evaluate(()=>tvSetMetric('rev')); await page.waitForTimeout(300);
  console.log('rev refused, metric:',await page.evaluate(()=>tvMetric),'| toast:',await page.evaluate(()=>document.getElementById('toastBox')?document.getElementById('toastBox').innerText.slice(0,60):'-'));
  console.log('PAGE ERRORS:',errs.length,errs.join(' | ')); await browser.close();
})();

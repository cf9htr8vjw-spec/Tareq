// شاشة الإيقاف: get_app_state=موقوف ⇒ الشاشة مخفية وتظهر رسالة الإيقاف؛ إعادة التشغيل بحساب أدمن ⇒ إعادة تحميل وعودة العرض
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:390,height:844}});
  const errs=[]; page.on('pageerror',e=>errs.push(e.message));
  let enabled=false, calls=[];
  await page.route('**/rest/v1/**',async route=>{
    const url=route.request().url(); const m=url.match(/rpc\/([a-z_]+)/);
    if(m&&m[1]==='get_app_state') return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({ok:true,enabled,message:'متوقف للصيانة حتى الساعة 5'})});
    if(m&&m[1]==='admin_set_app_state'){ const q=JSON.parse(route.request().postData()); calls.push(q);
      const ok=q.p_admin==='tareq'&&q.p_pass==='pw'; if(ok) enabled=q.p_enabled; return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(ok?{ok:true,msg:'أُعيد'}:{ok:false,msg:'غير مصرح'})}); }
    if(!enabled) return route.fulfill({status:401,contentType:'application/json',body:'{"message":"permission denied"}'});
    return route.fulfill({status:404,contentType:'application/json',body:'{"message":"mock"}'});
  });
  await page.goto(process.env.URL,{waitUntil:'load'}); await page.waitForTimeout(1200);
  const st=()=>page.evaluate(()=>({stop:!!document.getElementById('appStop'),msg:(document.getElementById('appStopMsg')||{}).textContent,
     tv:(document.getElementById('tvView')||{style:{}}).style.visibility, app:(document.getElementById('app')||{style:{}}).style.visibility, lock:(document.getElementById('lock')||{style:{}}).style.visibility}));
  console.log('stopped:',JSON.stringify(await st()));
  await page.screenshot({path:'/tmp/pwtest/stop.png'});
  await page.click('#appStop summary'); await page.fill('#appStopU','tareq'); await page.fill('#appStopP','bad'); await page.click('#appStopGo'); await page.waitForTimeout(400);
  console.log('bad pass:',await page.textContent('#appStopErr'));
  await page.fill('#appStopP','pw'); await page.click('#appStopGo'); await page.waitForTimeout(2500);
  console.log('after restart:',JSON.stringify(await st()), 'calls:',calls.length);
  console.log('PAGE ERRORS:',errs.length,errs.join(' | '));
  await browser.close();
})();

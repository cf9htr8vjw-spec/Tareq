const GW=require('/tmp/pwtest/gw.js'); const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{ const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const res={};
  for(const [name,url,mob] of [['login','file:///home/user/Tareq/SalesPlace_01.html',1],['phone','file:///home/user/Tareq/SalesPlace_01.html?tv=1&m=1',1],['board','file:///home/user/Tareq/SalesPlace_01.html?tv=1',0]]){
    const p=await b.newPage({viewport:mob?{width:390,height:844}:{width:1920,height:1080},isMobile:!!mob,hasTouch:!!mob});
    await p.route('**/rest/v1/**',GW(async r=>r.fulfill({status:404,contentType:'application/json',body:'{"message":"x"}'})));
    if(name!=='login') await GW.init(p);
    await p.goto(url); await p.waitForTimeout(2000); res[name]=await require('/tmp/pwtest/a11ylabels.js')(p); await p.close(); }
  console.log(JSON.stringify(res,null,1)); await b.close(); })();

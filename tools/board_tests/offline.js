const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage({viewport:{width:1366,height:768}}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.route('**/rest/v1/**',r=>r.abort('failed'));
  await p.goto(process.env.URL,{waitUntil:'load'}); await p.waitForTimeout(1500);
  console.log(await p.evaluate(()=>[tvKpiContracts.innerText, tvLeaders.innerText, tvTape.innerText.slice(0,60), tvSource.innerText].join(' || ')));
  console.log('errors',errs.length,errs.join('|'));
  await p.screenshot({path:process.env.OUT}); await b.close();
})();

const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', headless: true, args:['--no-sandbox'] });
  const page = await browser.newPage();
  const errors = [];
  page.on('console', msg => { if (msg.type()==='error') errors.push(msg.text()); });
  page.on('pageerror', err => errors.push('PAGEERROR: '+err.message));
  await page.goto('file:///home/user/Tareq/SalesPlace_01.html', {waitUntil:'load', timeout:30000});
  await page.waitForTimeout(1500);
  console.log('CONSOLE ERRORS:', errors.length);
  errors.forEach(e=>console.log(' -', e));
  const ids = ['lock','salesView','devMgmtView','supplyView','modelAnalyticsSheet','maModelList','maSummary'];
  for (const id of ids) {
    const exists = await page.$('#'+id) !== null;
    console.log(id, exists ? 'FOUND' : 'MISSING');
  }
  await browser.close();
})();

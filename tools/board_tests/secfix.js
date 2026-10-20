const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html?tv=1',{waitUntil:'load'}); await p.waitForTimeout(500);
  console.log(JSON.stringify(await p.evaluate(()=>{
    const R=(pn,city,sec,st,d)=>({"project_name":pn,"المدينة":city,"القطاع":sec,"حالة الحجز":st,"تاريخ توقيع العقد":d,"developer_name":"NHC","unit_type":"villa","price":800000});
    const rows=[R("أراك","المدينة المنورة","الغربي","متاحة على المنصة"),R("أراك","المدينة المنورة","","عقد","2026-05-01"),R("أراك","المدينة المنورة",null,"عقد","2026-06-01"),
      R("الندى","مكة المكرمة","منطقة مكة","عقد","2026-07-01"),R("رحاب","مكة المكرمة","الغربي","عقد","2026-07-02"),R("مجهول","مدينة جديدة","","عقد","2026-07-03")];
    const a=tvAllocAggregate(rows,null); return {fixed:a.secFixed,unknown:a.secUnknown,c:a.contracts.map(c=>c.project_name+':'+c.sector)};
  })));
  console.log('ERR',errs.length); await b.close();
})();

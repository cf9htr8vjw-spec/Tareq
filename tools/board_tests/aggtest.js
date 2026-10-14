const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html',{waitUntil:'load'}); await p.waitForTimeout(600);
  console.log(JSON.stringify(await p.evaluate(()=>{
    const rows=[
      {"حالة الحجز":"عقد","تاريخ توقيع العقد":46300,"القطاع":"الأوسط","developer_name":"NHC","price":1,"unit_type":"apartment","اسم البنك":"","سعر العقد":"1,250,000","نوع المستفيدين":"المستفيدين","moh_price":1100000,"القنوات":"مركز بيع","موقع العمل":"-","Employee Name":"-","project_name":"خزام بارك","project_code":"02-01-0117","الضاحية":"خزام"},
      {"حالة الحجز":"عقد ","تاريخ توقيع العقد":"2026-10-03","القطاع":"الغربي","developer_name":"X","price":900000,"unit_type":"Villa","اسم البنك":"مصرف الراجحي","سعر العقد":null,"project_name":"ب","القنوات":"مبيعات_الهاتف","موقع العمل":"مبيعات الهاتف","المسمى الوظيفي":"AGENT","Employee Name":"هلا حامد"},
      {"حالة الحجز":"متاحة على المنصة","القطاع":"الأوسط","developer_name":"NHC","project_name":"خزام بارك","project_code":"02-01-0117","الضاحية":"خزام"},
      {"حالة الحجز":"عقد","تاريخ توقيع العقد":null,"القطاع":"الأوسط","developer_name":"NHC","project_name":"ج"},
    ];
    const a=tvAllocAggregate(rows,n=>n==="خزام بارك"?"خزام بارك ريزيدنس":null);
    return {channels:a.channels,employees:a.employees,keys:[a.chanKey,a.empKey],value:a.value,contracts:a.contracts,banks:a.banks,status:a.status.map(s=>s.project_name+'/'+s.status+'/'+s.app_name),priceKey:a.priceKey,bankKey:a.bankKey,year:a.contractsYear,noDate:a.noDate};
  }),null,0));
  console.log('PAGE ERRORS:',errs.length);
  await b.close();
})();

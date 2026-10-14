// تجميع المنتجات/النماذج من صفوف ملف التخصيص (tvAllocAggregate.products)
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.goto('file:///home/user/Tareq/NHC_Live_Board.html',{waitUntil:'load'}); await p.waitForTimeout(600);
  console.log(JSON.stringify(await p.evaluate(()=>{
    const today=new Date(), iso=d=>d.toISOString().slice(0,10), ago=n=>iso(new Date(today-n*864e5));
    const base={project_name:"خزام بارك",project_code:"P1",developer_name:"NHC","القطاع":"الأوسط","المدينة":"الرياض","الضاحية":"خزام",unit_type:"apartment",model:"A",Number_of_Bedrooms:3,unit_size:150};
    const rows=[
      {...base,"حالة الحجز":"متاحة على المنصة",price:800000,moh_price:700000},
      {...base,"حالة الحجز":"متاحة لدى المطور",price:820000,unit_size:160},
      {...base,"حالة الحجز":"حجز","تاريخ الحجز":ago(5)},
      {...base,"حالة الحجز":"عقد","تاريخ توقيع العقد":ago(10),price:780000},
      {...base,"حالة الحجز":"عقد","تاريخ توقيع العقد":ago(60),price:790000},
      {...base,"حالة الحجز":"عقد","تاريخ توقيع العقد":"2024-03-01",price:600000},
      {...base,"حالة الحجز":"محجوب"},
      {...base,model:"B",unit_type:"villa",Number_of_Bedrooms:5,unit_size:300,"حالة الحجز":"عقد","تاريخ توقيع العقد":ago(2),price:1500000},
    ];
    const a=tvAllocAggregate(rows,null);
    return {keys:[a.modelKey,a.bedsKey,a.sizeKey],products:a.products};
  }),null,0));
  console.log('PAGE ERRORS:',errs.length,errs.join('|'));
  await b.close();
})();

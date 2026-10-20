// صفوف تجريبية بأعمدة ملف التخصيص الجديد (84 عموداً: REDF، قناة الحجز، البنك، بلا Employee Name — EMP=1 يضيف الموظفين) → tvAllocAggregate → JSON
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const fs=require('fs');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message)); await p.route('**/rest/v1/**',r=>r.fulfill({status:404,body:'{}'}));
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html?tv=1'); await p.waitForTimeout(400);
  const out=await p.evaluate(withEmp=>{
    let seed=7; const rnd=()=>{ seed=(seed*16807)%2147483647; return seed/2147483647; }, pick=a=>a[Math.floor(rnd()*a.length)];
    const today=new Date(), iso=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
    const projs=[["خزام بارك","NHC","خزام","الأوسط","الرياض"],["الفرسان ريزيدنس","NHC","الفرسان","الأوسط","الرياض"],["سدايم جاردنز","شركة روشن","سدايم","الأوسط","الرياض"],
      ["الوريف بارك","NHC","الوريف","الغربي","جدة"],["مكة هيلز","دار الأركان","مكة هيلز","الغربي","مكة المكرمة"],["الدمام الجديدة","NHC","الدمام الجديدة","الشرقي","الدمام"]];
    const ch=[["مطور",.5],["مركز بيع",.25],["مبيعات الرقمية",.15],["مبيعات الهاتف",.1]];
    const banks=[["الراجحي",.039],["الأهلي",.0468],["الرياض",.046],["الإنماء",.0395],["البلاد",.046],["العربي الوطني",.0449],["السعودي الفرنسي",.043],["",0]];
    const jobs=["موظف حكومي","موظف حكومي","قطاع خاص","عسكري","متقاعد"];
    const rows=[];
    for(let i=0;i<4200;i++){ const pj=pick(projs), dAgo=Math.floor(Math.pow(rnd(),1.3)*300), cd=new Date(today-dAgo*864e5), bd=new Date(cd-Math.floor(5+rnd()*80)*864e5);
      let r=rnd(), c=ch[0][0]; for(const [n,w] of ch){ if(r<w){ c=n; break; } r-=w; }
      const bk=pick(banks), cash=!bk[0], fa=cash?null:Math.round(450000+rnd()*700000), m=cash?null:pick([240,300,360]);
      rows.push({units_Id:i,project_name:pj[0],project_code:"P"+projs.indexOf(pj),developer_name:pj[1],"الضاحية":pj[2],"القطاع":pj[3],"المدينة":pj[4],unit_type:pick(["apartment","villa","townhouse"]),
        model:"model_"+pick(["A","B","C"]),unit_size:120+Math.round(rnd()*200),Number_of_Bedrooms:pick([2,3,4]),"هوية المستفيد":"1000000000",
        "حالة الحجز":"عقد","تاريخ الحجز":iso(bd),"تاريخ توقيع العقد":iso(cd),price:600000+Math.round(rnd()*1400000),moh_price:500000,"نوع المستفيدين":rnd()<.8?"المستفيدين":"غير المستفيدين",
        "البنك":bk[0],"قناة الحجز":c,"تاريخ بدء البيع للمشروع":"2025-03-01",
        "REDF - نسبة الأرباح":cash?null:+(bk[1]*100+(rnd()-.4)*0.5).toFixed(2),"مدة التمويل بالأشهر- REDF":m,"اجمالي مبلغ التمويل - REDF":fa,
        "الراتب  - REDF":cash?null:Math.round(9000+rnd()*16000),"القسط الشهرى - REDF":cash?null:Math.round(fa/m),"جهة العمل - REDF":cash?null:pick(jobs),"عدد أفراد الأسرة -REDF":cash?null:1+Math.floor(rnd()*7),
        "مبلغ باقة دعم الدفعة المقدمة":rnd()<.3?Math.round(rnd()*150000):null,"الدعم العينى":rnd()<.4?"Yes":"No","مبلغ الدعم العيني":rnd()<.4?150000:null,
        "مستفيد مبادرة العسكريين":rnd()<.1?1:0,"مبادرة الدعم الإضافى عسكريين - الصندوق":rnd()<.05?"Yes":"No","منتج ذرى بلس":rnd()<.06?"1":"0"}); }
    for(let i=0;i<900;i++){ const pj=pick(projs), bd=new Date(today-Math.floor(rnd()*160)*864e5);
      rows.push({project_name:pj[0],project_code:"P"+projs.indexOf(pj),developer_name:pj[1],"الضاحية":pj[2],"القطاع":pj[3],"المدينة":pj[4],unit_type:"apartment","حالة الحجز":"حجز","تاريخ الحجز":iso(bd),
        "تاريخ عقد الاستصناع":rnd()<.35?iso(bd):null,"قناة الحجز":pick(ch)[0],"البنك":"",price:800000}); }
    if(withEmp) rows.forEach((r,i)=>{ if(r["حالة الحجز"]==="عقد"){ r["Employee Name"]=["سارة","خالد","منيرة","فهد","هلا","تركي"][i%6]+" "+(i%17); r["موقع العمل"]=["الوسطى","الغربية","الشرقية"][i%3]; } });
    allocDropCols(rows);
    const a=tvAllocAggregate(rows,null);
    return {keys:[a.rateKey,a.termKey,a.chanKey,a.empKey,a.bankKey],fin:a.finKeys,idLeft:rows.some(r=>"هوية المستفيد" in r),daily:a.opsDaily,book:a.opsBook};
  },!!process.env.EMP);
  fs.writeFileSync(process.argv[2],JSON.stringify(out));
  console.log('keys',out.keys,'fin',JSON.stringify(out.fin),'idLeft',out.idLeft,'daily rows',out.daily.length,'book rows',out.book.length,'contracts',out.daily.reduce((x,r)=>x+r.n,0),'rated',out.daily.reduce((x,r)=>x+r.rn,0),'fa n',out.daily.reduce((x,r)=>x+(r.fan||0),0));
  console.log('ERR',errs); await b.close();
})();

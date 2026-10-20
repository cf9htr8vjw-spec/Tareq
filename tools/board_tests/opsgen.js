// صفوف تخصيص تجريبية → tvAllocAggregate (كود الشاشة) → opsDaily/opsBook JSON
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const fs=require('fs');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message)); await p.route('**/rest/v1/**',r=>r.fulfill({status:404,body:'{}'}));
  await p.goto('file:///home/user/Tareq/NHC_Live_Board.html'); await p.waitForTimeout(400);
  const out=await p.evaluate(()=>{
    let seed=11; const rnd=()=>{ seed=(seed*16807)%2147483647; return seed/2147483647; }, pick=a=>a[Math.floor(rnd()*a.length)];
    const today=new Date(), iso=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
    const projs=[["خزام بارك","NHC","خزام","الأوسط","الرياض"],["الفرسان ريزيدنس","NHC","الفرسان","الأوسط","الرياض"],["سدايم جاردنز","شركة روشن","سدايم","الأوسط","الرياض"],
      ["الوريف بارك","NHC","الوريف","الغربي","جدة"],["مكة هيلز","دار الأركان","مكة هيلز","الغربي","مكة المكرمة"],["الدمام الجديدة","NHC","الدمام الجديدة","الشرقي","الدمام"]];
    const ch=[["مركز بيع",.45],["مبيعات الرقمية",.25],["مبيعات الهاتف",.18],["البيع المباشر",.12]];
    const banks=[["مصرف الراجحي",.039],["البنك الأهلي السعودي",.0468],["الأهلي - التمويل البديل",.0375],["بنك الرياض",.046],["مصرف الإنماء",.0395],["بنك البلاد",.046],["البنك العربي الوطني",.0449],["البنك السعودي الفرنسي",.043],["-",0]];
    const emps=Array.from({length:24},(_,i)=>["سارة","خالد","منيرة","فهد","هلا","تركي","نورة","ماجد"][i%8]+" "+["العتيبي","الغامدي","الحربي","الشهري","الدوسري","القحطاني"][i%6]+" "+(i+1));
    const works=["الوسطى","الغربية","الشرقية","مبيعات الهاتف","البيع المباشر"];
    const rows=[];
    for(let i=0;i<4200;i++){ const pj=pick(projs), dAgo=Math.floor(Math.pow(rnd(),1.3)*300), cd=new Date(today-dAgo*864e5), bd=new Date(cd-Math.floor(5+rnd()*80)*864e5);
      let r=rnd(), c=ch[0][0]; for(const [n,w] of ch){ if(r<w){ c=n; break; } r-=w; }
      const bk=pick(banks), cash=bk[0]==="-", e=emps[Math.floor(Math.pow(rnd(),1.6)*emps.length)];
      rows.push({project_name:pj[0],project_code:"P"+projs.indexOf(pj),developer_name:pj[1],"الضاحية":pj[2],"القطاع":pj[3],"المدينة":pj[4],unit_type:pick(["apartment","villa","townhouse"]),
        "حالة الحجز":"عقد","تاريخ الحجز":iso(bd),"تاريخ توقيع العقد":iso(cd),price:600000+Math.round(rnd()*1400000),moh_price:500000,"نوع المستفيدين":rnd()<.8?"المستفيدين":"غير المستفيدين",
        "اسم البنك":bk[0],"القنوات":c,"موقع العمل":works[emps.indexOf(e)%5],"Employee Name":rnd()<.95?e:"-",
        "نسبة الربح":cash?null:+(bk[1]*100+(rnd()-.4)*0.5).toFixed(2),"مدة التمويل":cash?null:pick([20,25,30])}); }
    for(let i=0;i<900;i++){ const pj=pick(projs), bd=new Date(today-Math.floor(rnd()*160)*864e5);
      rows.push({project_name:pj[0],project_code:"P"+projs.indexOf(pj),developer_name:pj[1],"الضاحية":pj[2],"القطاع":pj[3],"المدينة":pj[4],unit_type:"apartment","حالة الحجز":"حجز","تاريخ الحجز":iso(bd),
        "تاريخ عقد الاستصناع":rnd()<.35?iso(bd):null,"القنوات":pick(ch)[0],price:800000}); }
    const a=tvAllocAggregate(rows,null);
    return {keys:[a.rateKey,a.termKey,a.chanKey,a.empKey,a.bankKey],daily:a.opsDaily,book:a.opsBook};
  });
  fs.writeFileSync(process.argv[2],JSON.stringify(out));
  console.log('keys',out.keys,'daily rows',out.daily.length,'book rows',out.book.length,'contracts',out.daily.reduce((x,r)=>x+r.n,0),'rated',out.daily.reduce((x,r)=>x+r.rn,0));
  console.log('ERR',errs); await b.close();
})();

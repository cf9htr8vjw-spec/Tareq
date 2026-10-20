// صفوف تجريبية بأعمدة قالب ملف التخصيص الصحيح (القنوات بشرطة سفلية، موقع العمل = المنطقة، Employee Name، سعر العقد، أعمدة REDF)
// الأسماء من قائمة الموظفين (JSON من tvRosterRead) ليُختبر «بلا عقود بالفترة». الاستعمال: node opsgen3.js out.json roster.json
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const fs=require('fs');
(async()=>{
  const roster=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message)); await p.route('**/rest/v1/**',r=>r.fulfill({status:404,body:'{}'}));
  await p.goto('file:///home/user/Tareq/NHC_Live_Board.html'); await p.waitForTimeout(400);
  const out=await p.evaluate(roster=>{
    let seed=5; const rnd=()=>{ seed=(seed*16807)%2147483647; return seed/2147483647; }, pick=a=>a[Math.floor(rnd()*a.length)];
    const today=new Date(), iso=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
    const projs=[["خزام بارك","NHC","خزام","الأوسط","الرياض"],["الفرسان ريزيدنس","NHC","الفرسان","الأوسط","الرياض"],["سدايم جاردنز","شركة روشن","سدايم","الأوسط","الرياض"],
      ["الوريف بارك","NHC","الوريف","الغربي","جدة"],["بوابة مكة","دار الأركان","بوابة مكة","الغربي","مكة المكرمة"],["الرشا","NHC","الرشا","الشرقي","الدمام"]];
    const ch=[["مركز_بيع",.6],["المبيعات_الرقمية",.2],["مبيعات_الصفقات",.1],["مبيعات_الهاتف",.1]];
    const banks=[["الراجحي",.039],["الأهلي",.0468],["الرياض",.046],["الإنماء",.0395],["البلاد",.046],["العربي",.0449],["الفرنسي",.043],["",0]];
    const D2S={"الوسطى":"الأوسط","الغربية":"الغربي","الشرقية":"الشرقي"};
    const act=roster.filter(r=>!r.resigned&&/agent/i.test(r.job)), sellers=Object.keys(D2S).flatMap(d=>act.filter(r=>r.district===d).slice(0,25));
    const rows=[];
    for(let i=0;i<4200;i++){ const pj=pick(projs), dAgo=Math.floor(Math.pow(rnd(),1.3)*300), cd=new Date(today-dAgo*864e5), bd=new Date(cd-Math.floor(5+rnd()*80)*864e5);
      let r=rnd(), c=ch[0][0]; for(const [n,w] of ch){ if(r<w){ c=n; break; } r-=w; }
      const bk=pick(banks), cash=!bk[0], m=cash?null:pick([104,180,240,300,360]), fa=cash?null:Math.round(450000+rnd()*700000);
      const sl=sellers.filter(s=>D2S[s.district]===pj[3]), e=rnd()<.8&&sl.length?sl[Math.floor(Math.pow(rnd(),1.4)*sl.length)]:null;
      rows.push({units_Id:i,project_name:pj[0],project_code:"P"+projs.indexOf(pj),developer_name:pj[1],"الضاحية":pj[2],"القطاع":pj[3],"المدينة":pj[4],unit_type:pick(["apartment","villa"]),
        "حالة الحجز":"عقد","تاريخ الحجز":iso(bd),"تاريخ توقيع العقد":iso(cd),price:900000,moh_price:800000,"سعر العقد":600000+Math.round(rnd()*1400000),"نوع المستفيدين":rnd()<.8?"المستفيدين":"غير المستفيدين",
        "البنك":bk[0],"القنوات":c,"موقع العمل":e?e.district+" ":"-","المسمى الوظيفي":e?"AGENT":"-","Employee Name":e?e.name:"-",
        "REDF - نسبة الأرباح":cash?null:+(bk[1]*100+0.8+(rnd()-.4)*1.5).toFixed(2),"مدة التمويل بالأشهر- REDF":m,"اجمالي مبلغ التمويل - REDF":fa,
        "الراتب  - REDF":cash?null:Math.round(9000+rnd()*16000),"القسط الشهرى - REDF":cash?null:Math.round(fa/m),"جهة العمل - REDF":cash?null:pick(["موظف حكومي","موظف حكومي","قطاع خاص","عسكري"]),"عدد أفراد الأسرة -REDF":cash?null:1+Math.floor(rnd()*7),
        "الدعم العينى - REDF":rnd()<.4?"Yes":"No","مبلغ الدعم العيني - REDF":rnd()<.4?Math.round(20000+rnd()*150000):0,"نوع التمويل - REDF":"باقة دعم الدفعة المقدمة","مبلغ دعم الدفعة المقدمة - REDF":pick([100000,150000])}); }
    for(let i=0;i<900;i++){ const pj=pick(projs), bd=new Date(today-Math.floor(rnd()*160)*864e5);
      rows.push({project_name:pj[0],project_code:"P"+projs.indexOf(pj),developer_name:pj[1],"الضاحية":pj[2],"القطاع":pj[3],"المدينة":pj[4],unit_type:"apartment","حالة الحجز":"حجز","تاريخ الحجز":iso(bd),
        "تاريخ عقد الاستصناع":rnd()<.35?iso(bd):null,"القنوات":pick(ch)[0],"البنك":"",price:800000}); }
    allocDropCols(rows);
    const a=tvAllocAggregate(rows,null);
    return {keys:[a.rateKey,a.termKey,a.chanKey,a.empKey,a.bankKey,a.priceKey],fin:a.finKeys,daily:a.opsDaily,book:a.opsBook};
  },roster);
  fs.writeFileSync(process.argv[2],JSON.stringify(out));
  console.log('keys',out.keys,'fin',JSON.stringify(out.fin),'daily',out.daily.length,'contracts',out.daily.reduce((x,r)=>x+r.n,0),'rated',out.daily.reduce((x,r)=>x+r.rn,0),'flat n',out.daily.reduce((x,r)=>x+(r.fln||0),0),'chans',[...new Set(out.daily.map(r=>r.ch))].join('|'));
  console.log('ERR',errs); await b.close();
})();

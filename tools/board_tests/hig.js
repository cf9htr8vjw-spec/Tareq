const GW=require('/tmp/pwtest/gw.js');
const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const mk=(c,b,a,s,i,f,ca,nb,sb,p)=>({contracts:c,bookings:b,available:a,supply:s,inventory:i,financed:f,cash:ca,nonbene:nb,selfbuild:sb,projects_with_contracts:p});
const t=(h,m)=>{const d=new Date();d.setHours(h,m,0,0);return d.toISOString();};
const today=(()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;})();
const names=[['بنان بي بي أربعة','شركه مجموعه طلعت مصطفي السعودية للتطوير العقاري','الرياض',0,16],['بنان ثمانية','شركه مجموعه طلعت مصطفي السعودية للتطوير العقاري','الرياض',0,11],['الندى','NHC','مكة المكرمة',1,3],['رحاب الربى','NHC','الرياض',1,3],['ملفى تبوك هيلز','فيصل بن سعيدان','تبوك',0,3],['ملفى جدة','فيصل بن سعيدان','جدة',0,3],['إيال سدايم','الحبيب','الرياض',0,3],['بنان 6','شركه مجموعه طلعت مصطفي السعودية للتطوير العقاري','الرياض',0,2],['أزيان الفرسان','شركة التطوير الشامل للتطوير العقاري','الرياض',0,2],['دانية الغروب','NHC','جدة',1,2],['جوهرة الربى','عبدالرحمن الراشد','الرياض',0,2],['ريفان','شركة مايا للاستثمار و التطوير العقاري','الدمام',0,2],['أورا هايتس','ديار الرائدة','الدمام',0,2],['رحاب الأصالة','NHC','الرياض',1,2],['أصيل الغروب 2','شركة الامباط للمقاولات','جدة',0,2]];
for(let i=0;i<30;i++) names.push([`مشروع تجريبي ${i+1}`, i%4?'مطوّر تجريبي':'NHC', ['الرياض','جدة','الخبر'][i%3], i%4?0:1, 1]);
const SEC_OF={'الرياض':'الأوسط','مكة المكرمة':'الغربي','جدة':'الغربي','تبوك':'الغربي','الدمام':'الشرقي','الخبر':'الشرقي'};
const movers=names.map(([p,d,c,n,k],i)=>({project:p,developer:d,city:c,sector:i===6?'غير محدد':SEC_OF[c],is_nhc:!!n,contracts:k,bookings:10+i*3,available:200+i*10,d_prev:i<5?1+(i%2):0,d_first:Math.max(1,k-1),b_prev:0}));
const feed=[...movers.slice(0,5).map(m=>({at:t(14,40),project:m.project,developer:m.developer,city:m.city,is_nhc:m.is_nhc,dc:m.d_prev,db:0,contracts:m.contracts})),
 ...movers.slice(3,9).map(m=>({at:t(13,30),project:m.project,developer:m.developer,city:m.city,is_nhc:m.is_nhc,dc:1,db:0,contracts:m.contracts-1}))];
function ST(){ const snaps={a:[t(14,40),[['الأوسط',1,11,800],['الأوسط',0,44,2600],['الغربي',1,6,300],['الغربي',0,25,1200],['الشرقي',1,3,200],['الشرقي',0,14,470]]],
  b:[t(13,30),[['الأوسط',1,9,795],['الأوسط',0,40,2590],['الغربي',1,5,300],['الغربي',0,22,1190],['الشرقي',1,3,200],['الشرقي',0,12,470]]],
  c:[t(8,10),[['الأوسط',1,2,790],['الأوسط',0,5,2580],['الغربي',1,1,300],['الغربي',0,2,1185],['الشرقي',1,0,200],['الشرقي',0,2,465]]]};
  const o=[]; Object.values(snaps).forEach(([at,rows])=>rows.forEach(([sector,nhc,c,bk])=>o.push({at,sector,nhc:!!nhc,contracts:c,bookings:bk,available:100,financed:Math.round(c*0.7),cash:1,nonbene:Math.round(c*0.2),selfbuild:0,projects_with_contracts:Math.ceil(c/3)}))); return o; }
const LIVE={ok:true,empty:false,day:today,latest_at:t(14,40),prev_at:t(13,30),first_at:t(8,10),snapshots_today:6,
 latest:{all:mk(103,5575,158321,34087,119603,59,7,37,0,58),nhc:mk(20,1309,44043,9100,30200,14,1,5,0,12),dev:mk(83,4266,114278,24987,89403,45,6,32,0,46)},
 prev:{all:mk(91,5560,158333,34087,119603,52,6,33,0,54),nhc:mk(17,1302,44046,9100,30200,12,1,4,0,11),dev:mk(74,4258,114287,24987,89403,40,5,29,0,43)},
 first:{all:mk(12,5490,158412,34087,119603,7,1,4,0,9),nhc:mk(3,1290,44060,9100,30200,2,0,1,0,2),dev:mk(9,4200,114352,24987,89403,5,1,3,0,7)},
 timeline:[{at:t(8,10),contracts:12,nhc:3},{at:t(9,30),contracts:31,nhc:6},{at:t(10,45),contracts:52,nhc:10},{at:t(12,0),contracts:70,nhc:13},{at:t(13,30),contracts:91,nhc:17},{at:t(14,40),contracts:103,nhc:20}],
 movers, feed, sector_totals:ST(), timeline_sector:[[8,10,7,2],[9,30,15,4],[10,45,25,6],[12,0,35,8],[13,30,49,9],[14,40,55,11]].map(([h,m,c,n])=>({at:t(h,m),sector:'الأوسط',contracts:c,nhc:n})), today_by_sector:{'الأوسط':55,'الغربي':31,'الشرقي':14,'غير محدد':3}};
const now=new Date(), cm=now.getMonth()+1, cd=now.getDate();
const YEAR=Array.from({length:cm},(_,i)=>({period:`${now.getFullYear()}-${String(i+1).padStart(2,'0')}`,cnt:[310,420,390,515,480,610,560,640,720,318,400,380][i]}));
const dayRows=scale=>Array.from({length:cd},(_,i)=>({period:`${now.getFullYear()}-${String(cm).padStart(2,'0')}-${String(i+1).padStart(2,'0')}`,cnt:Math.round([22,35,0,0,41,38,44,29,51,33,25,30,28,40,36,31,22,45,38,27,33,41,29,35,40,22,30,28,33,26,20][i]*scale)}));
const TGT={null:1100,'الأوسط':520,'الغربي':380,'الشرقي':200};
const SCALE={null:1,'الأوسط':0.55,'الغربي':0.28,'الشرقي':0.12};
const SECTOR={ok:true,rows:[['الأوسط','شقة',210],['الأوسط','فيلا',140],['الأوسط','تاون هاوس',40],['الغربي','شقة',150],['الغربي','فيلا',80],['الشرقي','شقة',60],['الشرقي','فيلا',40]].map(([s,u,c])=>({sector:s,unit_type:u,total_cnt:c,daily:Array.from({length:30},(_,d)=>({day:d+1,cnt:Math.round(c/30*(0.4+((d*7)%10)/8))}))}))};
const PRICING=[{sector:'الأوسط',avg_price:812000,avg_price_sqm:5100},{sector:'الغربي',avg_price:745000,avg_price_sqm:4210},{sector:'الشرقي',avg_price:690000,avg_price_sqm:3650}];
const MARKET=[['الرياض','شقة',770000,6537,16476],['الرياض','فيلا',1880000,4145,8053],['المدينة المنورة','شقة',740000,3591,1075],['المدينة المنورة','فيلا',750000,1538,1201],['مكة المكرمة','شقة',730000,4141,10013],['مكة المكرمة','فيلا',2040000,3149,3480],['تبوك','شقة',540000,2404,323],['تبوك','فيلا',630000,1087,511],['الشرقية','شقة',680000,3730,4724],['الشرقية','فيلا',1070000,2543,4266]].map(([r,p,a,s,d])=>({region:r,property_type:p,avg_price:a,avg_price_sqm:s,deals_ytd:d}));
const TODAY={ok:true,kingdom:{bookings:18,istisna:6,contracts:25},by_sector:[{sector:'الأوسط',bookings:9,istisna:3,contracts:14},{sector:'الغربي',bookings:6,istisna:2,contracts:8},{sector:'الشرقي',bookings:3,istisna:1,contracts:3}]};
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:+(process.env.VW||1920),height:+(process.env.VH||1080)},isMobile:!!process.env.MOBILE,hasTouch:!!process.env.MOBILE,deviceScaleFactor:process.env.MOBILE?2:1});
  const errs=[]; page.on('pageerror',e=>errs.push(e.message));
  await page.route('**/rest/v1/**',GW(async(route,__url,__post)=>{
    const url=__url; let body=null;
    { const mm=url.match(/rpc\/(get_tv_ops)$/); if(mm){ const q=JSON.parse(__post||'{}');
        if(process.env.NOOPS) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"Could not find the function public.get_tv_ops"}'});
        const L=v=>v==null?'null':"'"+String(v).replace(/'/g,"''")+"'";
        const sql=`select get_tv_ops(${L(q.p_from)}::date,${L(q.p_to)}::date,${L(q.p_sector)},${L(q.p_kind)},${L(q.p_dest)},${L(q.p_project)},${L(q.p_channel)})`;
        const out=require('child_process').execFileSync('psql',['-h','/tmp','-p','5499','-U','postgres','-d','t','-At','-c',sql]).toString();
        return route.fulfill({status:200,contentType:'application/json',body:out}); } }
    const m=url.match(/rpc\/([a-z_]+)/);
    if(m){ const fn=m[1]; const q=JSON.parse(__post||'{}'); const sec=q.p_sector??null;
      if(fn==='get_tv_contracts'){ if(process.env.NOFC) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"no fn"}'});
        const months=[]; const add=(sec,kind,q3,oc)=>{ for(let i=0;i<9;i++) months.push({m:i+1,sector:sec,kind,cnt:i<8?Math.floor(q3/9):q3-Math.floor(q3/9)*8}); months.push({m:10,sector:sec,kind,cnt:oc}); }; const RV=r=>process.env.NOREV?r:Object.assign(r,{fin:r.cnt*800000*0.6,cash:r.cnt*800000*0.4});
        add(process.env.VARIANT?'الوسطى':'الأوسط','nhc',2562,291); add('الغربي','nhc',3073,163); add('الشرقي','nhc',565,53); add('الأوسط','other',12000,1577);
        const days=dayRows(1).map(r=>RV({d:+r.period.slice(8),sector:'الأوسط',kind:'nhc',cnt:r.cnt})); months.forEach(RV);
        body={ok:true,rev_classified:process.env.NOREV?0:500,source:process.env.SRC||'file',months,days,file_sector_rows:process.env.FS0?0:1000,rows:1000,unmapped:process.env.VARIANT?[{v:'قطاع الأعمال',cnt:12}]:[]}; }
      else if(fn==='get_tv_revenue'){ if(process.env.NOREV) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"no fn"}'}); body=JSON.parse(require('fs').readFileSync('/tmp/pwtest/revenue.json','utf8')); const days=[]; for(let d=1;d<=12;d++) days.push({d,sector:['الأوسط','الغربي','الشرقي'][d%3],due:(d*37%11+2)*1.3e6}); body.days=days; body.months=Array.from({length:10},(_,i)=>({m:i+1,sector:'الأوسط',due:(i*7%5+3)*2.1e7})); }
      else if(fn==='get_tv_prices'){ if(process.env.NOPRICE) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"no fn"}'});
        const rows=[]; const d0=new Date(q.p_from+'T00:00:00'), d1=new Date(q.p_to+'T00:00:00'); let i=0;
        for(let d=new Date(d0); d<=d1; d.setDate(d.getDate()+1), i++){ const ds=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
          [['شقة',780000,0.18],['فيلا',1550000,0.22],['تاون هاوس',1100000,0.15]].forEach(([t,b,v],j)=>{ ['الأوسط','الغربي','الشرقي'].forEach((sec,k)=>{ const w=1+0.08*Math.sin(i/3+j+k)+0.002*i; const n=3+((i*7+j*3+k)%9);
            const p50=b*w; rows.push({d:ds,sector:sec,kind:k?'other':'nhc',type:t,n,psum:p50*n*1.02,min:p50*(1-v*1.6),max:p50*(1+v*(1.5+((i+j)%4)*0.6)),p25:p50*(1-v*0.5),p50,p75:p50*(1+v*0.55)}); }); }); }
        body={ok:true,from:q.p_from,to:q.p_to,rows}; }
      else if(fn==='get_tv_force'){ if(process.env.NOFORCE) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"no fn"}'});
        const today=q.p_from===q.p_to; const k=today?0:(q.p_from.endsWith('-01-01')?20:3);
        const ch=[['مركز بيع',120],['مبيعات الرقمية',60],['مبيعات الهاتف',35],['البيع المباشر',22],['',15]];
        const secs=['الأوسط','الغربي','الشرقي'];
        const names=['حجاب مشعل الحربي','هلا حامد علي البدر','حليمة علي الوبار','ثبات عبدالله محمد','سمر معيض المالكي','عبدالعزيز جلعود الحربي','عبدالرحيم عبدالله الزهراني','مقرن سلطان البهلال','حصة زيد سعود الدوسري','نايف شاهر العتيبي','نجوى عادل ابوكور','ريم سعد القحطاني','فهد ناصر الشهري','سارة محمد العمري','خالد عبدالله الغامدي','منيرة صالح الدوسري','تركي فيصل العنزي','نورة عبدالرحمن السبيعي','ماجد عوض المطيري','لمى حسن الزهراني','بندر سالم الحارثي','أمل يوسف الشمري'];
        const works=['الوسطى','الغربية','الشرقية','مبيعات الهاتف','البيع المباشر'];
        body={ok:true,has_channels:true,has_employees:true,
          channels:k?ch.flatMap(([c,n],i)=>secs.map((s,j)=>({sector:s,kind:j?'other':'nhc',channel:c,cnt:Math.round(n*k/(j+1)/3)}))):[],
          avail:[['الأوسط','nhc','شقة',420,30],['الأوسط','other','فيلا',310,80],['الغربي','nhc','شقة',200,0],['الغربي','other','تاون هاوس',45,12],['الشرقي','other','فيلا',90,40]].map(([sector,kind,type,platform,developer])=>({sector,kind,type,platform,developer})),
          employees:k?names.map((n,i)=>({sector:secs[i%3],kind:i%4?'other':'nhc',employee:n,work:works[i%5],cnt:Math.max(1,Math.round((40-i*1.6)*k/3))})):[]}; }
      else if(fn==='get_tv_market'){ if(process.env.NOMKT) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"no fn"}'});
        const C=[['الرياض','شقة',5860,850000,[546,189,120]],['الرياض','فيلا',5370,1850000,[165,59,40]],['جدة','شقة',3649,620000,[236,195,141]],['جدة','فيلا',4300,2300000,[36,8,19]],['مكة المكرمة','شقة',5200,550000,[42,30,30]],['المدينة المنورة','فيلا',4980,310000,[41,29,34]],['الدمام','شقة',3140,610000,[65,29,20]],['الخبر','شقة',3750,970000,[40,18,12]],['الطائف','فيلا',1920,540000,[18,37,56]],['أبها','شقة',2250,390000,[12,11,18]]];
        const rows=[]; [202640,202641,202642].forEach((wk,i)=>C.forEach(([c,t,sqm,avg,d])=>rows.push([wk,c,t,d[i],d[i]*avg,wk===202640?'2026-08':'2026-09',sqm,i===1?3:0])));
        body={ok:true,as_of:new Date().toISOString(),weeks:[202640,202641,202642],cols:['wk','city','type','deals','value','month','sqm','excluded'],rows}; }
      else if(fn==='get_tv_product_stats'){ if(process.env.NOPS) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"Could not find the function get_tv_product_stats"}'});
        const cols=['project','code','model','type','beds','developer','kind','sector','city','dest','avail_p','avail_d','reserved','contracts','c30','c90','cy','b30','months','pa_sum','pa_n','ps_sum','ps_n','moh_sum','moh_n','sz_sum','sz_n','sz_min','sz_max','sqa_p','sqa_s','sqs_p','sqs_s','launch','avail_b','avail_n','c30b','c90b','cyb','lat','lon','sqa_m'];
        const places=[['الأوسط','الرياض','خزام'],['الأوسط','الرياض','الفرسان'],['الأوسط','الرياض','سدايم'],['الغربي','جدة','الوريف'],['الغربي','مكة المكرمة','مكة هيلز'],['الغربي','المدينة المنورة','بوابة المدينة'],['الشرقي','الدمام','الدمام الجديدة'],['الشرقي','الخبر','الخبر الشمالية']];
        const types=[['شقة',[2,3,4],[110,140,175],[650e3,820e3,980e3]],['فيلا',[4,5,6],[260,320,400],[1.4e6,1.75e6,2.3e6]],['تاون هاوس',[3,4],[180,220],[1.05e6,1.25e6]]];
        let seed=7; const rnd=()=>{ seed=(seed*16807)%2147483647; return seed/2147483647; };
        const rows=[];
        places.forEach(([sec,city,dest],pi)=>{ for(let pj=0;pj<3;pj++){ const proj=`${dest} ${['بارك','ريزيدنس','جاردنز'][pj]}`, kind=pj===0?'nhc':'other', dev=kind==='nhc'?'NHC':['شركة روشن','دار الأركان','الماجدية'][pi%3];
          types.forEach(([t,beds,szs,prs],ti)=>{ if(ti===2&&pj===2) return; beds.forEach((b,bi)=>{ ['A','B'].forEach((m,mi)=>{
            const off=Math.round(20+rnd()*180), absr=Math.min(.98,Math.max(.12,(.35+.5*rnd())*(t==='شقة'&&b===3?1.25:t==='فيلا'&&b===6?.6:1)*(sec==='الأوسط'?1.1:.95)));
            const sold=Math.round(off*absr), con=Math.round(sold*.8), res=sold-con, avail=off-sold, ap=Math.round(avail*.8), ad=avail-ap;
            const cy=Math.round(con*(.3+.4*rnd())), mo=Array.from({length:12},(_,k)=>k<10?Math.round(cy/10*(0.6+0.8*rnd())):0), c90=mo[7]+mo[8]+mo[9], c30=mo[9];
            const sz=szs[bi]*(0.93+0.14*rnd())+(mi?10:0), pr=prs[bi]*(0.9+0.25*rnd())*(sec==='الأوسط'?1.08:sec==='الشرقي'?.88:1);
            rows.push([proj,'P'+pi+pj,m+(bi+1),t,b,dev,kind,sec,city,dest,ap,ad,res,con,c30,c90,cy,Math.round(res*.5),mo,
              Math.round(pr*ap),ap,Math.round(pr*.97*con),con,Math.round(pr*.86*ap),ap,Math.round(sz*off),off,Math.round(sz*.95),Math.round(sz*1.05),Math.round(pr*ap),Math.round(sz*ap),Math.round(pr*.97*con),Math.round(sz*con),null,Math.round(avail*(kind==='nhc'?.85:.5)),Math.round(avail*(kind==='nhc'?.3:.8)),Math.round(c30*.7),Math.round(c90*.65),Math.round(cy*.7),null,null,Math.round(pr*.86*ap)]); }); }); }); } });
        body={ok:true,as_of:new Date().toISOString(),year:new Date().getFullYear(),cols,rows}; }
      else if(fn==='get_tv_employee_months'){ const n=new Date().getMonth()+1;
        body={ok:true,employee:q.p_employee,year:q.p_year,first_date:`${q.p_year}-01-01`,total:0,rank:3,employees:42,work:[{work:'الوسطى',cnt:30},{work:'مبيعات الهاتف',cnt:5}],
          months:Array.from({length:12},(_,k)=>({m:k+1,cnt:k<n?Math.round(8+10*Math.abs(Math.sin(k*1.3))):0,team_avg:k<n?+(6+3*Math.abs(Math.cos(k))).toFixed(1):null,team_max:k<n?22+k:null}))};
        body.total=body.months.reduce((a,m)=>a+m.cnt,0); }
      else if(fn==='get_tv_destinations'){ if(process.env.NODEST) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"no fn"}'});
        const D=[['خزام','الأوسط',820,1460,1200,4100,950,210],['الفرسان','الأوسط',610,300,900,800,400,30],['سدايم','الأوسط',140,90,700,600,1200,0],['الوريف','الغربي',300,1450,794,3000,500,120],['مكة هيلز','الغربي',90,600,0,1500,300,40],['بوابة مكة','الغربي',0,700,0,2000,900,0],['الدمام الجديدة','الشرقي',120,800,600,2600,700,90],['الخبر الشمالية','الشرقي',30,200,0,900,200,10]];
        const NN=+(process.env.DESTN||8); while(D.length<NN){ const b=D[D.length%8]; D.push([b[0]+' '+D.length,b[1],b[2],b[3],b[4],b[5],b[6],b[7]]); } D.length=NN;
        body={ok:true,diag:{status_rows:process.env.DIAG0?0:5000,status_dest_rows:3000,contract_rows:900,contract_project_rows:900},as_of:new Date(Date.now()-5*3600e3).toISOString(),rows:D.map(([dest,sector,nhc,dev,nt,dt,ap,ad])=>({dest,sector,nhc,dev,nhc_target:nt,dev_target:dt,avail_platform:ap,avail_developer:ad})),
          avail_by_sector:{'الأوسط':{platform:20100,developer:3000,nhc_platform:5000,nhc_developer:0,dev_platform:15100,dev_developer:3000},'الغربي':{platform:15000,developer:1500,nhc_platform:3800,nhc_developer:0,dev_platform:11200,dev_developer:1500}},avail:{platform:41230,developer:5120,nhc_platform:9800,nhc_developer:0,dev_platform:31430,dev_developer:5120},targets_outside:{nhc:900,dev:12000}}; }
      else if(fn==='get_tv_products'){ if(process.env.NOPROD) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"no fn"}'});
        const ytd=q.p_from.endsWith('-01-01'); const k=ytd?1:0.08; const rows=[];
        [['الأوسط',1],['الغربي',1.2],['الشرقي',0.3]].forEach(([sec,w])=>{ [['nhc',0.25],['other',1]].forEach(([kind,kw])=>{ [['شقة',600,820000],['فيلا',300,1650000],['تاون هاوس',60,1150000]].forEach(([type,c,p])=>{ const cnt=Math.round(c*w*kw*k)||1; rows.push({sector:sec,kind,type,cnt,psum:cnt*p*(0.9+w/10),pn:cnt}); }); }); });
        body={ok:true,from:q.p_from,to:q.p_to,rows,market_month:'2026-09-01',market:[['الرياض','شقة',630000,2443],['الرياض','فيلا',1870000,690],['مكة المكرمة','شقة',610000,1168],['مكة المكرمة','فيلا',4120000,337],['المدينة المنورة','شقة',800000,96],['المدينة المنورة','فيلا',690000,121],['تبوك','شقة',730000,37],['تبوك','فيلا',520000,51],['الشرقية','شقة',640000,525],['الشرقية','فيلا',880000,310]].map(([region,type,avg_price,deals])=>({region,type,avg_price,deals}))}; }
      else if(fn==='get_tv_memo_scope'){ const M=[]; [['الأوسط',2300,250],['الغربي',2900,150],['الشرقي',520,50]].forEach(([sec,q3,oc])=>{ for(let i=0;i<9;i++) M.push({m:i+1,sector:sec,cnt:Math.round(q3/9)}); M.push({m:10,sector:sec,cnt:oc}); }); body={ok:true,months:M,targets:32,matched:30,file_projects:41,unmatched:['أراسي','مريفة']}; }
      else if(fn==='get_tv_banks'){ body={ok:true,has_banks:!process.env.NOBANK,rows:[['الأوسط','nhc','مصرف الراجحي',120],['الأوسط','other','البنك الأهلي السعودي',95],['الغربي','other','مصرف الراجحي',80],['الغربي','nhc','بنك الرياض',40],['الشرقي','other','البنك العربي الوطني',22],['الأوسط','other','مصرف الإنماء',30],['الغربي','other','البنك السعودي الفرنسي',18],['الأوسط','nhc','',15]].map(([sector,kind,bank,cnt])=>({sector,kind,bank,cnt}))}; }
      else if(fn==='get_tv_period_projects'){ body={ok:true,from:q.p_from,to:q.p_to,as_of:new Date(Date.now()-5*3600e3).toISOString(),rows:movers.slice(0,25).map((m,i)=>({project:m.project,is_nhc:m.is_nhc,developer:m.developer,city:m.city,sector:m.sector,cnt:(q.p_from===q.p_to?3:20)+((i*7)%11),fin:((i*13)%7+1)*1.1e6,cash:((i*5)%4)*9e5}))}; }
      else if(fn==='get_dashboard_targets')body={ok:true,year:now.getFullYear(),scopes:{nhc:{total:14081,projects:32,by_sector:{'الأوسط':4677,'الغربي':6135,'الشرقي':3269},rev_total:2570870060,rev_by_sector:{'الأوسط':1073830730,'الشرقي':206751395,'الغربي':1290287935}},dev:{total:70645,projects:178,by_sector:{}}}};
      else if(fn==='get_sales_report' && q.p_granularity==='month' && q.p_dev_kind){ const QO={nhc:{null:[6200,507],'الأوسط':[2562,291],'الغربي':[3073,163],'الشرقي':[565,53]},other:{null:[12000,1577]}}[q.p_dev_kind][sec]||[0,0]; const [q3,oc]=QO; body=Array.from({length:cm},(_,i)=>({period:`${now.getFullYear()}-${String(i+1).padStart(2,'0')}`,cnt: i<9 ? (i<8?Math.floor(q3/9):q3-Math.floor(q3/9)*8) : (i===9?oc:0)})); }
      else if(fn==='get_live_board'){ if(process.env.LIVETIMEOUT) return route.fulfill({status:500,contentType:'application/json',body:JSON.stringify({message:'canceling statement due to statement timeout'})}); body=process.env.VARIANT?{...LIVE,today_by_sector:{'الاوسط':40,'الوسطى':15,'الغربي':31,'الشرقي':14}}:LIVE; } else if(fn==='get_sales_report')body=q.p_granularity==='month'?YEAR:dayRows(SCALE[sec]); else if(fn==='get_target_summary')body={total:TGT[sec],by_project:[]}; else if(fn==='get_sector_type_sales')body=SECTOR; else if(fn==='get_sector_avail_pricing')body=PRICING; else if(fn==='get_today_activity')body=TODAY; }
    else if(url.includes('market_price_stats')) body=MARKET;
    else if(url.includes('sync_status')) body=[{last_synced_at:t(7,5)}];
    if(body===null) return route.fulfill({status:404,contentType:'application/json',body:'{"message":"mock"}'});
    return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
  }));
  await GW.init(page);
  const A=require('/tmp/pwtest/higaudit.js'); const OUT={};
  const MODE=process.env.MODE||'phone'; const opt=Object.assign(MODE==='phone'?{minText:11,tDef:44,tMin:28}:MODE==='tv'?{minText:23,tDef:66,tMin:56}:{minText:10,tDef:28,tMin:20},{rules:!!process.env.RULES});
  if(process.env.NOSESS){ await page.goto(process.env.URL,{waitUntil:'load'}); await page.waitForTimeout(1200); OUT.login=await A(page,opt); console.log(JSON.stringify(OUT)); await browser.close(); return; }
  await GW.init(page);
  await page.goto(process.env.URL,{waitUntil:'load'}); await page.waitForTimeout(2500);
  if(MODE==='phone'){
    for(const t of ['today','projects','charts','ops','analysis','map']){ await page.click(`#mNav button[data-tab="${t}"]`); await page.waitForTimeout(1800); OUT[t]=await A(page,Object.assign({full:true},opt)); }
  } else {
    for(const n of [1,2,3,4]){ await page.click(`#tvPageDots i:nth-child(${n})`); await page.waitForTimeout(2200); OUT['p'+n]=await A(page,opt); }
    await page.mouse.move(300,300); await page.mouse.move(320,320); await page.waitForTimeout(400); await page.evaluate(()=>tvUpOpen()); await page.waitForTimeout(400); OUT.upload=await A(page,opt);
  }
  console.log(JSON.stringify(OUT)); await browser.close();
})();

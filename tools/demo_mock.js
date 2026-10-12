/* نسخة تجريبية لشاشة المبيعات الحيّة: يعترض كل نداءات قاعدة البيانات ويُرجع بيانات وهمية مولّدة
   بالمتصفح (أسماء مشاريع وبنوك عامة، أرقام عشوائية ثابتة البذرة). لا اتصال بأي قاعدة بيانات، والرفع معطّل.
   يُحقن في NHC_Live_Board_DEMO.html بواسطة tools/build_demo_board.py */
(function(){
  const now=new Date(), Y=now.getFullYear(), M=now.getMonth()+1, D=now.getDate();
  const pad=n=>String(n).padStart(2,"0");
  const iso=d=>`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
  const TODAY=iso(now);
  let seed=20261012; const rnd=()=>{ seed=(seed*16807)%2147483647; return seed/2147483647; };
  const ri=(a,b)=>a+Math.floor(rnd()*(b-a+1));
  const SECS=["الأوسط","الغربي","الشرقي"];
  const CITY={"الأوسط":["الرياض","القصيم"],"الغربي":["جدة","مكة المكرمة","المدينة المنورة"],"الشرقي":["الدمام","الخبر"]};
  const DEVS=["مطوّر تجريبي أ","مطوّر تجريبي ب","مطوّر تجريبي ج","مطوّر تجريبي د","مطوّر تجريبي هـ"];
  const DESTS=[];
  SECS.forEach((s,si)=>{ for(let i=1;i<=[6,5,3][si];i++) DESTS.push({dest:`وجهة تجريبية ${s.replace("ال","")} ${i}`,sector:s}); });
  /* المشاريع */
  const P=[];
  for(let i=1;i<=64;i++){
    const r=rnd(), sec=r<0.45?"الأوسط":r<0.85?"الغربي":"الشرقي";
    const nhc=rnd()<0.28, d=DESTS.filter(x=>x.sector===sec);
    P.push({project:`مشروع تجريبي ${i}`,sector:sec,city:CITY[sec][ri(0,CITY[sec].length-1)],is_nhc:nhc,
      developer:nhc?"NHC":DEVS[ri(0,DEVS.length-1)],dest:rnd()<0.7?d[ri(0,d.length-1)].dest:"",w:0.3+rnd()*2});
  }
  /* السحوبات الساعية اليوم */
  const startH=8, nowH=Math.max(startH+1,Math.min(20,now.getHours()));
  const pulls=[]; for(let h=startH;h<=nowH;h+=1) pulls.push(new Date(Y,M-1,D,h,ri(0,50)).toISOString());
  const todayFinal=P.map(p=>rnd()<0.7?Math.round(p.w*ri(0,6)):0);
  const snap=k=>P.map((p,i)=>{ const f=(k+1)/pulls.length; return {...p,contracts:Math.round(todayFinal[i]*Math.min(1,f*(0.8+rnd()*0.4))),bookings:ri(5,90),available:ri(50,900),financed:0,cash:0,nonbene:0,selfbuild:0}; });
  const snaps=pulls.map((_,k)=>snap(k));
  snaps[snaps.length-1].forEach((r,i)=>{ r.contracts=todayFinal[i]; });
  snaps.forEach(s=>s.forEach(r=>{ r.financed=Math.round(r.contracts*0.7); r.cash=Math.round(r.contracts*0.1); r.nonbene=r.contracts-r.financed-r.cash; }));
  const sum=(rows,f)=>{ const o={contracts:0,bookings:0,available:0,financed:0,cash:0,nonbene:0,selfbuild:0,projects_with_contracts:0};
    rows.filter(f||(()=>true)).forEach(r=>{ ["contracts","bookings","available","financed","cash","nonbene","selfbuild"].forEach(k=>o[k]+=r[k]); if(r.contracts>0) o.projects_with_contracts++; }); return o; };
  const tot=s=>({all:sum(s),nhc:sum(s,r=>r.is_nhc),dev:sum(s,r=>!r.is_nhc)});
  const L=snaps.length-1, last=snaps[L], prev=L>0?snaps[L-1]:null, first=snaps[0];
  const movers=last.map((r,i)=>({project:r.project,developer:r.developer,city:r.city,sector:r.sector,is_nhc:r.is_nhc,contracts:r.contracts,bookings:r.bookings,available:r.available,
      d_prev:prev?r.contracts-prev[i].contracts:null,d_first:r.contracts-first[i].contracts,b_prev:0})).filter(m=>m.contracts>0).sort((a,b)=>b.contracts-a.contracts);
  const feed=[]; for(let k=1;k<snaps.length;k++) snaps[k].forEach((r,i)=>{ const dc=r.contracts-snaps[k-1][i].contracts; if(dc>0) feed.push({at:pulls[k],project:r.project,developer:r.developer,city:r.city,sector:r.sector,is_nhc:r.is_nhc,dc,db:0,contracts:r.contracts}); });
  feed.sort((a,b)=>b.at.localeCompare(a.at));
  const sectorTotals=[]; [[L,pulls[L]],[L-1,pulls[L-1]],[0,pulls[0]]].forEach(([k,at])=>{ if(k<0) return; SECS.forEach(sec=>[true,false].forEach(n=>{ const t=sum(snaps[k],r=>r.sector===sec&&r.is_nhc===n); sectorTotals.push({at,sector:sec,nhc:n,...t}); })); });
  const LIVE={ok:true,empty:false,day:TODAY,latest_at:pulls[L],prev_at:L>0?pulls[L-1]:null,first_at:pulls[0],snapshots_today:pulls.length,
    latest:tot(last),prev:prev?tot(prev):{},first:tot(first),
    timeline:snaps.map((s,k)=>({at:pulls[k],contracts:sum(s).contracts,nhc:sum(s,r=>r.is_nhc).contracts})),
    timeline_sector:snaps.flatMap((s,k)=>SECS.map(sec=>({at:pulls[k],sector:sec,contracts:sum(s,r=>r.sector===sec).contracts,nhc:sum(s,r=>r.sector===sec&&r.is_nhc).contracts}))),
    sector_totals:sectorTotals,movers,feed:feed.slice(0,60),
    today_by_sector:Object.fromEntries(SECS.map(sec=>[sec,sum(last,r=>r.sector===sec).contracts]))};

  /* العقود من ملف التخصيص: شهري ويومي لكل قطاع × NHC/مطور */
  const BASE={"الأوسط":{nhc:300,other:1050},"الغربي":{nhc:350,other:700},"الشرقي":{nhc:62,other:230}};
  const daysIn=m=>new Date(Y,m,0).getDate();
  const MONTHS=[], DAYS=[];
  SECS.forEach(sec=>["nhc","other"].forEach(kind=>{ for(let m=1;m<=M;m++){
    const full=Math.round(BASE[sec][kind]*(0.75+rnd()*0.5)), cnt=m<M?full:Math.round(full*(D-1)/daysIn(m));
    MONTHS.push({m,sector:sec,kind,cnt});
    if(m===M){ let left=cnt; for(let d=1;d<D;d++){ const c=d===D-1?left:Math.round(cnt/(D-1)*(0.5+rnd())); const cc=Math.max(0,Math.min(left,c)); DAYS.push({d,sector:sec,kind,cnt:cc}); left-=cc; } }
  }}));
  const MEMO=MONTHS.filter(r=>r.kind==="nhc").map(r=>({m:r.m,sector:r.sector,cnt:Math.round(r.cnt*0.9)}));
  const TYPES=[["شقة",0.62,820000],["فيلا",0.3,1650000],["تاون هاوس",0.08,1150000]];
  const daysBetween=(a,b)=>Math.max(0,Math.round((new Date(b)-new Date(a))/864e5)+1);
  const yearDays=(new Date(Y,M-1,D)-new Date(Y,0,1))/864e5+1;
  const scaleFor=(from,to)=>{ const to2=to>=TODAY?iso(new Date(now.getTime()-864e5)):to; return from>to2?0:daysBetween(from,to2)/yearDays; };
  const YTD={}; MONTHS.forEach(r=>{ const k=r.sector+"|"+r.kind; YTD[k]=(YTD[k]||0)+r.cnt; });
  const products=(from,to)=>{ const f=scaleFor(from,to), rows=[];
    SECS.forEach(sec=>["nhc","other"].forEach(kind=>TYPES.forEach(([type,share,price])=>{ const cnt=Math.round((YTD[sec+"|"+kind]||0)*share*f); if(cnt) rows.push({sector:sec,kind,type,cnt,psum:cnt*price*(0.92+rnd()*0.16),pn:cnt}); })));
    return rows; };
  const BANKS=[["بنك تجريبي أ",0.34],["بنك تجريبي ب",0.22],["بنك تجريبي ج",0.16],["بنك تجريبي د",0.12],["بنك تجريبي هـ",0.09],["بنك تجريبي و",0.07]];
  const banks=(from,to)=>{ const f=scaleFor(from,to), rows=[];
    SECS.forEach(sec=>["nhc","other"].forEach(kind=>{ const n=Math.round((YTD[sec+"|"+kind]||0)*f); BANKS.forEach(([b,sh])=>{ const c=Math.round(n*0.8*sh); if(c) rows.push({sector:sec,kind,bank:b,cnt:c}); }); if(n) rows.push({sector:sec,kind,bank:"",cnt:Math.round(n*0.2)}); }));
    return rows; };
  const period=(from,to)=>{ const f=scaleFor(from,to);
    return P.map(p=>({project:p.project,is_nhc:p.is_nhc,developer:p.developer,city:p.city,sector:p.sector,dest:p.dest||null,cnt:Math.round(p.w*f*yearDays*0.9*(0.5+rnd()))})).filter(r=>r.cnt>0).sort((a,b)=>b.cnt-a.cnt); };
  const MARKET=[["الرياض","شقة",630000,5884,2443],["الرياض","فيلا",1870000,3919,690],["مكة المكرمة","شقة",610000,3832,1168],["مكة المكرمة","فيلا",4120000,3257,337],["المدينة المنورة","شقة",800000,3780,96],["المدينة المنورة","فيلا",690000,1116,121],["تبوك","شقة",730000,2600,37],["تبوك","فيلا",520000,824,51],["الشرقية","شقة",640000,3566,525],["الشرقية","فيلا",880000,1907,310]]
    .map(([region,type,avg_price,avg_price_sqm,deals])=>({region,type,avg_price,avg_price_sqm,deals}));
  const NHC_T={"الأوسط":4677,"الغربي":6135,"الشرقي":3269}, DEV_T={"الأوسط":38000,"الغربي":24000,"الشرقي":8645};
  const destRows=DESTS.map(d=>{ const ps=P.filter(p=>p.dest===d.dest), nhc=ps.filter(p=>p.is_nhc).reduce((a,p)=>a+Math.round(p.w*90),0), dev=ps.filter(p=>!p.is_nhc).reduce((a,p)=>a+Math.round(p.w*160),0);
    return {dest:d.dest,sector:d.sector,nhc,dev,nhc_target:nhc?Math.round(nhc*(1.1+rnd())):0,dev_target:dev?Math.round(dev*(1.2+rnd()*2)):0,avail_platform:ri(100,1500),avail_developer:ri(0,300)}; });
  const avail=rows=>({platform:rows.reduce((a,r)=>a+r.avail_platform,0),developer:rows.reduce((a,r)=>a+r.avail_developer,0),
    nhc_platform:Math.round(rows.reduce((a,r)=>a+r.avail_platform,0)*0.25),nhc_developer:0,dev_platform:Math.round(rows.reduce((a,r)=>a+r.avail_platform,0)*0.75),dev_developer:rows.reduce((a,r)=>a+r.avail_developer,0)});

  const RPC={
    get_live_board:()=>LIVE,
    get_dashboard_targets:()=>({ok:true,year:Y,scopes:{nhc:{total:14081,projects:32,by_sector:NHC_T},dev:{total:70645,projects:178,by_sector:DEV_T}}}),
    get_tv_contracts:()=>({ok:true,source:"file",months:MONTHS,days:DAYS,file_sector_rows:1,rows:1,unmapped:[]}),
    get_tv_memo_scope:()=>({ok:true,months:MEMO,targets:32,matched:30,file_projects:41,unmapped:[]}),
    get_tv_destinations:()=>({ok:true,as_of:new Date(Y,M-1,D,7,5).toISOString(),rows:destRows,diag:{status_rows:1,status_dest_rows:1},
      avail:avail(destRows),avail_by_sector:Object.fromEntries(SECS.map(s=>[s,avail(destRows.filter(r=>r.sector===s))])),targets_outside:{nhc:0,dev:0}}),
    get_tv_period_projects:q=>({ok:true,from:q.p_from,to:q.p_to,as_of:new Date(Y,M-1,D,7,5).toISOString(),rows:period(q.p_from,q.p_to)}),
    get_tv_products:q=>({ok:true,rows:products(q.p_from,q.p_to),market_month:`${Y}-09-01`,market:MARKET}),
    get_tv_banks:q=>({ok:true,has_banks:true,rows:banks(q.p_from,q.p_to)}),
    get_sector_type_sales:()=>({ok:true,rows:SECS.flatMap(sec=>TYPES.map(([t,sh])=>{ const c=Math.round((BASE[sec].nhc+BASE[sec].other)*sh); return {sector:sec,unit_type:t,total_cnt:c,daily:Array.from({length:28},(_,d)=>({day:d+1,cnt:Math.round(c/28*(0.5+rnd()))}))}; }))}),
    get_sector_avail_pricing:()=>SECS.map((s,i)=>({sector:s,avail_count:ri(2000,9000),avg_price:[812000,745000,690000][i],avg_price_sqm:[5100,4210,3650][i]})),
    get_today_activity:()=>({ok:true,kingdom:{bookings:38,istisna:11,contracts:LIVE.latest.all.contracts},by_sector:SECS.map(s=>({sector:s,bookings:ri(5,20),istisna:ri(1,6),contracts:LIVE.today_by_sector[s]}))}),
    get_sales_report:()=>[],
  };
  const TABLES={
    market_price_stats:()=>MARKET.map(m=>({region:m.region,property_type:m.type,avg_price:m.avg_price,avg_price_sqm:m.avg_price_sqm,deals_ytd:m.deals*9})),
    sync_status:()=>[{last_synced_at:new Date(Y,M-1,D,7,5).toISOString()}],
  };
  const realFetch=window.fetch.bind(window);
  window.fetch=async(url,opts)=>{
    const u=String(url), m=u.match(/\/rest\/v1\/rpc\/([a-z_]+)/), t=u.match(/\/rest\/v1\/([a-z_]+)\?/);
    const json=(b,st)=>new Response(JSON.stringify(b),{status:st||200,headers:{"Content-Type":"application/json"}});
    if(m){ const fn=m[1], q=opts&&opts.body?JSON.parse(opts.body):{};
      if(fn==="login"||/^admin_/.test(fn)) return json({ok:false,msg:"نسخة تجريبية — الرفع والحذف معطّلان"});
      if(RPC[fn]) return json(RPC[fn](q));
      return json({message:"غير متاح بالنسخة التجريبية"},404); }
    if(t){ const off=Number((u.match(/offset=(\d+)/)||[])[1]||0); return json(TABLES[t[1]]&&!off?TABLES[t[1]]():[]); }
    return realFetch(url,opts);
  };
})();

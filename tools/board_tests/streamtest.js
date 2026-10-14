const fs=require('fs'); const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args:['--no-sandbox','--js-flags=--max-old-space-size=8192']});
  const p=await b.newPage(); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.goto('file:///home/user/Tareq/SalesPlace_01.html',{waitUntil:'load'}); await p.waitForTimeout(600);
  const D=process.argv[2];
  for(const f of process.argv.slice(3)){
    await p.setInputFiles('#syncFile',`${D}/${f}.xlsx`).catch(()=>{});
    const r=await p.evaluate(async()=>{
      const file=document.getElementById('syncFile').files[0]; const W=["project_name","حالة الحجز","price","unit_type","developer_name","القطاع"];
      let lib=null, libErr=null;
      try{ const wb=XLSX.read(new Uint8Array(await file.arrayBuffer()),{type:"array"}); const ws=xlsxBestSheet(wb,W); lib=ws?XLSX.utils.sheet_to_json(ws,{defval:null}):"undefined-sheet"; }catch(e){ libErr=e.message; }
      const t0=performance.now(); const st=await xlsxStreamRows(file,W,()=>{}); const ms=Math.round(performance.now()-t0);
      let same=null, diff="";
      if(Array.isArray(lib)){ same=lib.length===st.rows.length; for(let i=0;i<lib.length&&same;i++){ const a=JSON.stringify(lib[i]), b=JSON.stringify(st.rows[i]); if(a!==b){ same=false; diff=a.slice(0,200)+' VS '+b.slice(0,200); } } }
      return {size:(file.size/1048576).toFixed(1)+'MB', lib:Array.isArray(lib)?lib.length+' rows':(lib||libErr), stream:st.rows.length+' rows, sheet '+st.sheetName+' of '+st.sheetCount+', '+ms+'ms', same, diff, sample:JSON.stringify(st.rows[1]).slice(0,300)};
    });
    console.log(f, JSON.stringify(r,null,0));
  }
  console.log('PAGE ERRORS:',errs.length,errs.join('|'));
  await b.close();
})();

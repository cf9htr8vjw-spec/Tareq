// نسخ احتياطي واستعادة من نافذة الرفع ضد Postgres المحلي (app_backup.sql): DB=t3 (نسخة من t)
const GW=require('/tmp/pwtest/gw.js'); const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const cp=require('child_process'), fs=require('fs'); const DB=process.env.DB||'t3';
const psql=sql=>cp.execFileSync('psql',['-h','/tmp','-p','5499','-U','postgres','-d',DB,'-At','-q','-v','ON_ERROR_STOP=1'],{input:(process.env.TMO?"set statement_timeout='"+process.env.TMO+"';\n":'')+sql+';\n',maxBuffer:1<<28}).toString().trim();
const lit=v=>v===null||v===undefined?'null':typeof v==='boolean'||typeof v==='number'?String(v):typeof v==='object'?"'"+JSON.stringify(v).replace(/'/g,"''")+"'::jsonb":"'"+String(v).replace(/'/g,"''")+"'";
const counts=()=>psql("select string_agg(name||'='||(xpath('/row/c/text()',query_to_xml(format('select count(*) as c from public.%I',name),false,true,'')))[1]::text,' ' order by name) from app_backup_tables()");
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const ctx=await browser.newContext({viewport:{width:1366,height:768},acceptDownloads:true}); const page=await ctx.newPage();
  const errs=[]; page.on('pageerror',e=>errs.push(e.message)); let calls=0;
  await page.route('**/rest/v1/**',GW(async(route,url,post)=>{
    const m=url.match(/rpc\/([a-z_0-9]+)$/);
    if(m&&m[1]==='admin_sessions') return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({ok:true,sessions:[]})});
    if(m&&/^admin_backup_/.test(m[1])){ calls++; const q=JSON.parse(post||'{}'); const args=Object.entries(q).map(([k,v])=>`${k}=>${lit(v)}`).join(',');
      try{ const out=psql(`select ${m[1]}(${args})::text`); return route.fulfill({status:200,contentType:'application/json',body:out}); }
      catch(e){ return route.fulfill({status:400,contentType:'application/json',body:JSON.stringify({message:String(e.stderr||e.message).slice(0,300)})}); } }
    return route.fulfill({status:404,contentType:'application/json',body:'{"message":"not mocked"}'}); }));
  await GW.init(page);
  await page.goto('file:///home/user/Tareq/SalesPlace_01.html?tv=1'); await page.waitForTimeout(2500);
  await page.mouse.move(300,300); await page.mouse.move(320,320); await page.waitForTimeout(400); await page.click('#tvUpBtn'); await page.waitForTimeout(300);
  await page.fill('#tvUpUser','bk'); await page.fill('#tvUpPass','pw');
  const before=counts();
  const dlP=page.waitForEvent('download',{timeout:400000}); await page.click('#tvBkGo'); for(let i=0;i<200;i++){ await page.waitForTimeout(1500); const t=await page.textContent('#tvBkMsg'); if(i%4==0) console.log('  msg:',t.slice(0,160)); if(/تم|تعذّر/.test(t)) break; }
  const dl=await dlP;
  const f='/tmp/pwtest/bk_'+dl.suggestedFilename(); await dl.saveAs(f);
  console.log('download:',dl.suggestedFilename(),fs.statSync(f).size,'bytes | msg:',(await page.textContent('#tvBkMsg')).slice(0,160));
  const head=cp.execSync(`zcat ${f} | head -c 300`).toString(); console.log('head:',head.slice(0,200));
  // تخريب ثم استعادة
  psql("delete from api_allow where fn like 'get_%'; delete from tv_ops_book where ctid in (select ctid from tv_ops_book limit 100); insert into app_users(username,pass_hash,is_admin,is_active) values('newguy',crypt('x',gen_salt('bf')),false,true); insert into tv_market_weekly(wk,city,unit_type) values(209901,'x','y') on conflict do nothing");
  console.log('damaged differs:',counts()!==before);
  page.once('dialog',d=>d.accept('استعادة'));
  await page.setInputFiles('#tvBkFile',f);
  await page.waitForFunction(()=>/استُعيدت|توقفت|ليس/.test(document.getElementById('tvBkMsg').textContent),null,{timeout:180000});
  console.log('restore msg:',(await page.textContent('#tvBkMsg')).slice(0,200));
  const strip=x=>x.replace(/app_users=\d+ /,''); const after=counts(); console.log('counts equal after restore (users merged):',strip(after)===strip(before),'| users:',psql("select string_agg(username,',' order by username) from app_users"),'| admin still valid:',psql("select app_backup_is_admin('bk','pw')")); if(after!==before){ console.log('before',before); console.log('after ',after); }
  // إلغاء الاستعادة بلا تأكيد
  page.once('dialog',d=>d.accept('لا')); await page.setInputFiles('#tvBkFile',f); await page.waitForTimeout(800); console.log('cancel msg:',await page.textContent('#tvBkMsg'));
  // كلمة مرور خاطئة
  await page.evaluate(()=>{ tvUpCreds={u:'bk',p:'bad',name:'bk'}; }); await page.click('#tvBkGo'); await page.waitForTimeout(1500); console.log('bad pass msg:',await page.textContent('#tvBkMsg'));
  await page.screenshot({path:'/tmp/pwtest/bk.png'});
  console.log('rpc calls:',calls,'| PAGE ERRORS:',errs.length,errs.slice(0,3).join(' | ')); await browser.close();
})();

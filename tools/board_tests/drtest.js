// سيناريو ضياع الحساب: نسخة من SRC ← أداة إعادة البناء (شاشة الدخول) ← nhc_rebuild.sql على قاعدة فارغة DST ← استعادة البيانات بحساب restore_tmp ← مطابقة
const GW=require('/tmp/pwtest/gw.js'); const { chromium } = require('/tmp/pwtest/node_modules/playwright-core');
const cp=require('child_process'), fs=require('fs'); const SRC=process.env.SRC||'t3', DST=process.env.DST||'t5', BASE=process.env.BASE||'http://localhost:8765';
const psql=(db,sql)=>cp.execFileSync('psql',['-h','/tmp','-p','5499','-U','postgres','-d',db,'-At','-v','ON_ERROR_STOP=1'],{input:sql+';\n',maxBuffer:1<<28}).toString().trim();
const lit=v=>v===null||v===undefined?'null':typeof v==='boolean'||typeof v==='number'?String(v):typeof v==='object'?"'"+JSON.stringify(v).replace(/'/g,"''")+"'::jsonb":"'"+String(v).replace(/'/g,"''")+"'";
const sums=db=>psql(db,"select string_agg(name||'='||(xpath('/row/m/text()',query_to_xml(format('select md5(coalesce(string_agg(x::text,''|'' order by x::text),'''')) as m from public.%I x',name),false,true,'')))[1]::text,' ' order by name) from app_backup_tables() where name<>'app_users'");
let DB=SRC;
(async()=>{
  const browser=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome',headless:true,args:['--no-sandbox']});
  const ctx=await browser.newContext({viewport:{width:1366,height:768},acceptDownloads:true}); const errs=[];
  const route=async(route)=>GW(async(r,url,post)=>{ const m=url.match(/rpc\/([a-z_0-9]+)$/);
      if(m&&m[1]==='admin_sessions'){ const q=JSON.parse(post||'{}'); const ok=psql(DB,`select app_backup_is_admin(${lit(q.p_admin)},${lit(q.p_pass)})`)==='t'; return r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(ok?{ok:true,sessions:[]}:{ok:false,msg:'هذا الإجراء يتطلب صلاحية مدير'})}); }
      if(m&&/^admin_backup_/.test(m[1])){ const q=JSON.parse(post||'{}'); const args=Object.entries(q).map(([k,v])=>`${k}=>${lit(v)}`).join(',');
        try{ return r.fulfill({status:200,contentType:'application/json',body:psql(DB,`select ${m[1]}(${args})::text`)}); }catch(e){ return r.fulfill({status:400,contentType:'application/json',body:JSON.stringify({message:String(e.stderr||e.message).slice(0,300)})}); } }
      return r.fulfill({status:404,contentType:'application/json',body:'{"message":"not mocked"}'}); })(route);
  // 1) نسخة احتياطية من المصدر
  let page=await ctx.newPage(); page.on('pageerror',e=>errs.push(e.message)); await page.route('**/rest/v1/**',route); await GW.init(page);
  await page.goto(BASE+'/SalesPlace_01.html?tv=1'); await page.waitForTimeout(2500);
  await page.mouse.move(300,300); await page.mouse.move(320,320); await page.waitForTimeout(400); await page.click('#tvUpBtn');
  await page.fill('#tvUpUser','bk'); await page.fill('#tvUpPass','pw');
  const dlP=page.waitForEvent('download',{timeout:600000}); await page.click('#tvBkGo'); const dl=await dlP; const BK='/tmp/pwtest/dr_'+dl.suggestedFilename(); await dl.saveAs(BK);
  console.log('1 backup:',(await page.textContent('#tvBkMsg')).slice(0,120)); await page.close();
  // 2) أداة إعادة البناء من شاشة الدخول (بلا جلسة)
  page=await ctx.newPage(); page.on('pageerror',e=>errs.push(e.message)); await page.route('**/rest/v1/**',route);
  await page.goto(BASE+'/SalesPlace_01.html'); await page.waitForTimeout(1500);
  await page.click('#lockRbLink'); await page.setInputFiles('#rbFile',BK); await page.waitForTimeout(1200);
  console.log('2 picked:',await page.textContent('#rbMsg'));
  console.log('  sql button disabled before password:',await page.isDisabled('#rbGoSql'));
  await page.fill('#rbPass','Temp-Pass-123'); 
  const d2=page.waitForEvent('download'); await page.click('#rbGoSql'); const sqlDl=await d2; const SQLF='/tmp/pwtest/dr_rebuild.sql'; await sqlDl.saveAs(SQLF);
  console.log('  rebuild file:',sqlDl.suggestedFilename(),fs.statSync(SQLF).size,'bytes | has temp pw:',fs.readFileSync(SQLF,'utf8').includes("crypt('Temp-Pass-123'"));
  await page.fill('#rbUrl','https://newproj123.supabase.co'); await page.fill('#rbKey','sb_publishable_NEWKEY_abcdefghijklmnop');
  const d3=page.waitForEvent('download'); await page.click('#rbGoHtml'); const h=await d3; const HF='/tmp/pwtest/dr_app.html'; await h.saveAs(HF); const ht=fs.readFileSync(HF,'utf8');
  console.log('  new app:',h.suggestedFilename(),'| url set:',ht.includes('window.SB_URL = "https://newproj123.supabase.co";'),'| key set:',ht.includes('window.SB_KEY = "sb_publishable_NEWKEY_abcdefghijklmnop";'),'| same size ±:',Math.abs(ht.length-fs.readFileSync('/home/user/Tareq/SalesPlace_01.html','utf8').length));
  await page.screenshot({path:'/tmp/pwtest/dr_tool.png'}); await page.close();
  // 3) قاعدة فارغة + سكربت الإنشاء
  cp.execFileSync('psql',['-h','/tmp','-p','5499','-U','postgres','-d','postgres','-qc',`drop database if exists ${DST}`]); cp.execFileSync('psql',['-h','/tmp','-p','5499','-U','postgres','-d','postgres','-qc',`create database ${DST}`]);
  psql(DST,'create extension pgcrypto'); /* محلياً pgcrypto في public كما في المصدر؛ في Supabase موجود في extensions */
  cp.execFileSync('psql',['-h','/tmp','-p','5499','-U','postgres','-d',DST,'-q','-v','ON_ERROR_STOP=1','-f',SQLF]);
  console.log('3 rebuilt: tables',psql(DST,"select count(*) from pg_tables where schemaname='public'"),'| restore_tmp admin:',psql(DST,"select app_backup_is_admin('restore_tmp','Temp-Pass-123')"));
  // 4) استعادة البيانات بحساب restore_tmp
  DB=DST; page=await ctx.newPage(); page.on('pageerror',e=>errs.push(e.message)); await page.route('**/rest/v1/**',route); await GW.init(page);
  await page.goto(BASE+'/SalesPlace_01.html?tv=1'); await page.waitForTimeout(2500);
  await page.mouse.move(300,300); await page.mouse.move(320,320); await page.waitForTimeout(400); await page.click('#tvUpBtn');
  await page.fill('#tvUpUser','restore_tmp'); await page.fill('#tvUpPass','Temp-Pass-123');
  page.once('dialog',d=>d.accept('استعادة')); await page.setInputFiles('#tvBkFile',BK);
  await page.waitForFunction(()=>/استُعيدت|توقفت|ليس/.test(document.getElementById('tvBkMsg').textContent),null,{timeout:900000});
  console.log('4 restore:',(await page.textContent('#tvBkMsg')).slice(0,140));
  const a=sums(SRC), b=sums(DST); console.log('5 data identical to source:',a===b,'| users:',psql(DST,"select string_agg(username,',' order by username) from app_users"),'| restore_tmp gone:',psql(DST,"select not exists(select 1 from app_users where username='restore_tmp')"));
  if(a!==b){ const A=a.split(' '),B=b.split(' '); A.forEach((x,i)=>{ if(x!==B[i]) console.log('  diff',x,'vs',B[i]); }); }
  console.log('  old admin works on new db:',psql(DST,"select app_backup_is_admin('bk','pw')"),'| anon fns:',psql(DST,"select string_agg(p.proname,',' order by 1) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where nspname='public' and has_function_privilege('anon',p.oid,'execute') and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')"));
  console.log('PAGE ERRORS:',errs.length,errs.slice(0,3).join(' | ')); await browser.close();
})();

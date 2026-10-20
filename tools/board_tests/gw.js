// محاكي بوابة app_security.sql للاختبارات: login_v2 / session_info / api / api_read
// يفكّ طلب البوابة إلى الدالة أو الجدول الأصلي ويمرّره لمحاكي الاختبار القديم (handler(route,url,post)).
// GW.init(page) يزرع جلسة محفوظة قبل التحميل فيستعيدها التطبيق تلقائياً (بلا شاشة الدخول).
//   متغيرات البيئة: NOFIN=1 (بلا صلاحية مالية)، NOADMIN=1، TVKIND=1 (جلسة شاشة عرض)، NOSESS=1 (لا تزرع جلسة).
const BASE='https://ulueukkxixrdhorcogds.supabase.co/rest/v1/';
const sess=()=>({ok:true,user:'tareq',name:'طارق',admin:!process.env.NOADMIN,fin:!process.env.NOFIN,kind:process.env.TVKIND?'tv':'user',perms:{},onboarded:true,expires:new Date(Date.now()+36e5).toISOString(),key:process.env.DATAKEY||null});
const json=(route,body,status)=>route.fulfill({status:status||200,contentType:'application/json',body:JSON.stringify(body)});
function GW(handler){
  return async function(route){
    const req=route.request(); const url=req.url(); const post=req.postData()||'';
    const m=url.match(/rpc\/(login_v2|api|api_read)$/);
    if(!m) return handler(route,url,post);
    let q={}; try{ q=JSON.parse(post||'{}'); }catch(e){}
    if(m[1]==='login_v2'){ GW.logins.push(q); return json(route,q.p_pass==='wrong'?{ok:false,msg:'اسم المستخدم أو كلمة المرور غير صحيحة'}:Object.assign(sess(),{token:'T',user:q.p_user||'tareq',kind:q.p_kind||'user'})); }
    if(q.p_token!=='T') return json(route,{message:'SESSION_EXPIRED'},400);
    if(m[1]==='api_read'){ const p=Object.assign({},q.p_params||{}); const qs=new URLSearchParams(p).toString(); return handler(route,BASE+q.p_table+'?'+qs,''); }
    if(q.p_fn==='session_info') return json(route,sess());
    if(q.p_fn==='logout') return json(route,{ok:true});
    GW.calls.push({fn:q.p_fn,args:q.p_args||{}});
    const fn=q.p_fn==='get_tv_revenue_v2'?'get_tv_revenue':q.p_fn;     /* المحاكيات القديمة تعرف الاسم القديم */
    if(fn==='get_tv_revenue'&&process.env.NOFIN) return json(route,{message:'API_FIN'},400);
    return handler(route,BASE+'rpc/'+fn,JSON.stringify(q.p_args||{}));
  };
}
GW.calls=[]; GW.logins=[];
GW.init=async page=>{ if(process.env.NOSESS) return;
  await page.addInitScript(({kind})=>{ try{ (kind==='tv'?localStorage:sessionStorage).setItem('nhc_session',JSON.stringify({token:'T',kind})); sessionStorage.setItem('nhc_mode','board'); }catch(e){} },{kind:process.env.TVKIND?'tv':'user'}); };
GW.login=async(page,u,p)=>{ await page.fill('#uid',u||'tareq'); await page.fill('#pw',p||'good'); await page.click('#lockBtn'); await page.waitForFunction(()=>document.getElementById('lock').classList.contains('hide')||/خطأ|غير صحيحة|تعذّر/.test(document.getElementById('lockMsg').textContent),null,{timeout:15000}); };
module.exports=GW;

// Only Payroll's account endpoint needs native HTTP. REST/Auth and blob exports
// continue to use web fetch. Server JWT verification and role checks are unchanged.
export function accountFetch(webFetch,nativeRequest,app){
 return async(input,init={})=>{
  let url;try{url=new URL(typeof input==='string'?input:input.href);}catch{return webFetch(input,init);}
  if(app.kind!=='payroll'||url.origin!==app.supabaseUrl||url.pathname!=='/functions/v1/payroll-accounts')return webFetch(input,init);
  if(init.signal?.aborted)throw new DOMException('Request aborted','AbortError');
  const headers=Object.fromEntries(new Headers(init.headers).entries());
  if(!headers.authorization?.startsWith('Bearer '))throw Error('Sign in to manage accounts.');
  if(headers.origin)throw Error('Native account requests must not override Origin.');
  if((init.method||'GET').toUpperCase()!=='POST'||!headers['content-type']?.includes('application/json')||typeof init.body!=='string')throw Error('Account requests require a JSON POST.');
  const result=await nativeRequest({url:url.href,method:'POST',headers,data:JSON.parse(init.body),responseType:'text',disableRedirects:true,connectTimeout:15000,readTimeout:30000});
  if(init.signal?.aborted)throw new DOMException('Request aborted','AbortError');
  return new Response([204,205,304].includes(result.status)?null:typeof result.data==='string'?result.data:JSON.stringify(result.data),{status:result.status,headers:result.headers});
 };
}

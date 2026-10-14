// Parse only recovery links belonging to this app or its configured Auth service.
export function parseRecoveryLink(value,appOrigin){
 let url;try{url=new URL(value);}catch{throw Error('Paste the complete password-reset link from your email.');}
 if(![appOrigin,'https://uvowltyjnzqtozygalhf.supabase.co'].includes(url.origin))throw Error('This reset link does not belong to Payroll.');
 const hash=new URLSearchParams(url.hash.slice(1)),query=url.searchParams;
 const error=hash.get('error_description')||query.get('error_description');
 if(error)throw Error('This recovery link is invalid or expired. Request a new reset email.');
 const type=hash.get('type')||query.get('type');
 if(type!=='recovery')throw Error('Use a password-reset link, not an account-confirmation link.');
 const token_hash=query.get('token_hash')||query.get('token');
 if(token_hash&&/^[a-zA-Z0-9_-]{8,4096}$/.test(token_hash))return {type:'hash',token_hash};
 const access_token=hash.get('access_token'),refresh_token=hash.get('refresh_token');
 if(access_token&&refresh_token)return {type:'session',access_token,refresh_token};
 throw Error('This link has no recovery token. Request a new reset email.');
}
export function isRecoveryCallback(value){
 const u=new URL(value),h=new URLSearchParams(u.hash.slice(1));
 return u.searchParams.get('type')==='recovery'||h.get('type')==='recovery'||u.searchParams.has('error_description')||h.has('error_description');
}

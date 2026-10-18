import {createHandler} from './handler.js';
// Platform-managed environment values stay inside the Edge Function and are never returned or logged.
Deno.serve(createHandler({url:Deno.env.get('SUPABASE_URL')!,publicKey:Deno.env.get('SUPABASE_ANON_KEY')!,adminKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!}));

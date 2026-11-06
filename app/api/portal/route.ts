import {currentUser,rpc,sameOrigin} from '../../../lib/backend';
export const dynamic='force-dynamic';
const json=(d:unknown,s=200)=>Response.json(d,{status:s,headers:{'Cache-Control':'no-store'}});
export async function GET(){try{const u=await currentUser();if(!u)return json({error:'Accesso richiesto'},401);return json(await rpc('portal_snapshot',{},u.accessToken));}catch(e){return json({error:(e as Error).message},403);}}
export async function POST(req:Request){try{if(!sameOrigin(req))return json({error:'Origine non valida'},403);const u=await currentUser();if(!u)return json({error:'Accesso richiesto'},401);const b=await req.json();return json(await rpc('portal_mutate',{payload:b},u.accessToken));}catch(e){return json({error:(e as Error).message},400);}}

'use client';
import {ReactNode,useState} from 'react';
export default function ListPage<T>({items,resetKey,children}:{items:T[],resetKey:string,children:(items:T[])=>ReactNode}){
 const [position,setPosition]=useState({key:resetKey,page:0});
 const pages=Math.max(1,Math.ceil(items.length/50));const page=position.key===resetKey?Math.min(position.page,pages-1):0;
 return <>{children(items.slice(page*50,page*50+50))}{items.length>50&&<div className="toolbar"><button className="subtle" disabled={!page} onClick={()=>setPosition({key:resetKey,page:page-1})}>Precedenti</button><span>Pagina {page+1} di {pages} · {items.length} elementi</span><button className="subtle" disabled={page+1>=pages} onClick={()=>setPosition({key:resetKey,page:page+1})}>Successivi</button></div>}</>
}

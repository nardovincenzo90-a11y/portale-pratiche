'use client';

import {useEffect,useRef,useState} from 'react';
import Recorder from './Recorder';
import Portal from '../../components/Portal';
import {createExercise, profiles, type Role} from './exercise';
import styles from './training.module.css';

const lessons: { title:string; role:Role; view:string; instruction:string }[] = [
  {title:'Inserimento ASO',role:'inserimento',view:'Inserimento ASO',instruction:'Inserisci una pratica ASO con note e VO facoltativo. Poi apri I miei inserimenti.'},
  {title:'Recuperi VO',role:'recuperi',view:'Recuperi',instruction:'Scegli una pratica disponibile. Salva solo il VO e verifica che la pratica resti in coda.'},
  {title:'BO ATPAY',role:'atpay',view:'BO ATPAY',instruction:'Prendi la prima pratica. Salva FK15 e, per proseguire nel bacino tecnico, spunta la richiesta tecnica.'},
  {title:'Reclami',role:'recuperi',view:'Reclami',instruction:'Prendi in carico il reclamo. Salva Gestito per liberarlo o Chiusa per chiuderlo. Ripeti la prova con il profilo BO.'},
  {title:'Segnalazioni tecniche',role:'atpay',view:'Segnalazioni tecniche',instruction:'Prendi la segnalazione, salva una bozza o completa con il numero tecnico. Verifica che resti l’esito FK15.'},
  {title:'BOOM e accessi',role:'admin',view:'BOOM · Tutte le pratiche',instruction:'Prova il filtro per giorno, il CSV e la selezione multipla. Apri Utenti e permessi per vedere la gestione dei ruoli.'},
  {title:'Super Admin',role:'super_admin',view:'Utenti e permessi',instruction:'Controlla che Super Admin non compaia nella lista. Obiettivo pilota: +10% di fatturate, da verificare sui conteggi FK15, FK30 e FK03.'},
];
export default function Training(){
 const exercise=useRef<ReturnType<typeof createExercise>|null>(null);
 if(!exercise.current)exercise.current=createExercise();
 const [lesson,setLesson]=useState(0),[role,setRole]=useState<Role>('inserimento'),[revision,reset]=useState(0),[clean,setClean]=useState(false);
 const root = useRef<HTMLDivElement>(null);
 const controls = useRef<HTMLElement>(null);
 useEffect(() => {
   const element = controls.current;
   if (!element) return;
   const resize = new ResizeObserver(() => root.current?.style.setProperty('--training-height', element.offsetHeight + 'px'));
   resize.observe(element);
   return () => resize.disconnect();
 }, []);
 const chapter=lessons[lesson], instance=exercise.current;
 return <div className={styles.training} ref={root}><aside className={styles.controls} ref={controls}>
 <div className={styles.top}><b>BO ATPAY · Formazione</b><span>Dati fittizi</span><a href="/manuale-bo-atpay.pdf">Manuale PDF</a><Recorder/><button onClick={()=>setClean(!clean)}>{clean?'Mostra guida':'Riduci guida'}</button></div>
 {!clean&&<><div className={styles.chapters}>{lessons.map((item,index)=><button aria-pressed={lesson===index} key={item.title} onClick={()=>{setLesson(index);setRole(item.role)}}>{item.title}</button>)}</div><div className={styles.actions}><label>Profilo <select value={role} onChange={e=>setRole(e.target.value as Role)}>{Object.entries(profiles).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label><p>{chapter.instruction}</p><button onClick={()=>{exercise.current=createExercise();reset(revision+1)}}>Ripristina dati di prova</button></div></>}
 </aside><Portal key={role+':'+lesson+':'+revision} training={{initialView:role===chapter.role?chapter.view:'Panoramica',load:()=>instance.load(role),act:input=>instance.act(role,input)}}/></div>
}

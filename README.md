# Portale ASO / ATPAY

Web app Next.js su Vercel, PostgreSQL e autenticazione Supabase. Tabelle private in `portal_internal` nel progetto condiviso con PT-PRO; nessuna modifica alle tabelle o alle policy dell’app PT-PRO. Nessun nuovo piano a pagamento.

## Flusso operativo originale

ASO187/191 sono origini dell’inserimento, non code indipendenti. Tutte le pratiche confluiscono nella coda comune BO ATPAY. Il back office prende la prima disponibile in ordine di creazione. Una pratica BO attiva per operatore; se già in carico viene mantenuta. Esiti, note, richiami con VO e orario italiano 08–22, rilascio differite al successivo aggiornamento nella finestra operativa.

Reclami: caricamento amministratore con una riga per reclamo; scelta esplicita dell’operatore; testo e note distinti; Gestito libera l’assegnazione e consente di riprendere; Chiusa elimina la riga e conserva l’evento di audit.

## Ruoli

- `inserimento`: inserisce e consulta soltanto i propri invii; non lavora pratiche né reclami. Vede quantità aggregata della coda e attesa stimata (8 minuti per pratica).
- `atpay`: inserisce, prende in carico dalla coda BO, aggiorna proprie lavorazioni, sceglie e lavora reclami; non vede archivio completo né gestione utenti.
- `admin`: archivio completo BOOM, statistiche globali, reclami massivi, risorse, utenti e ruoli, messaggio globale e presenze.

I nove amministratori del codice originale sono stati abilitati nel database, separatamente dalla configurazione pubblica del repository. L’account proprietario preesistente resta amministratore. L’elenco ATPAY è nel foglio TEAM SOSPC originale, non accessibile dal collegamento corrente; non viene ricostruito per supposizione. La directory TEAM SOSPC ha le cinque colonne originali e un import tramite incolla-tabella. Le abilitazioni ATPAY si assegnano per email esatta nella gestione utenti.

## Registrazione

`/login` offre accesso, registrazione e recupero. Registrazione e ingresso al portale riservati a `@konecta.com`, salvo l’account proprietario già esistente. I nuovi account devono confermare l’email; il ruolo predefinito è Inserimento, non modificabile tramite metadata inviati dal browser. Il database verifica identità e ruolo a ogni operazione.

Prima dell’apertura a tutto il team verificare in Supabase Auth:

- Redirect URLs comprendenti `https://portale-pratiche.vercel.app/login` e `https://portale-pratiche.vercel.app/reset`, preservando quelle esistenti.
- Un servizio SMTP capace di inviare ai destinatari aziendali. L’invio reale e l’arrivo nelle caselle Konecta non sono stati collaudati dall’agente. Il servizio email predefinito Supabase ha restrizioni e limiti; non promettere onboarding illimitato senza questa verifica.

Non disabilitare la conferma email: gli amministratori sono individuati tramite indirizzi aziendali e la loro proprietà va verificata. Password e sessioni Auth sono condivise con l’infrastruttura esistente: il cambio password dello stesso account vale anche nelle altre app che lo usano. Il logout usa scope local.

## Altre funzioni ripristinate

Statistiche giorno/settimana/mese/tutto, produttività FK e rate orario, obiettivi dagli ultimi 30 giorni, trend, heatmap, fasce di traffico storico, attesa stimata, appunti personali persistenti, calendario personale nel browser, link sistemi con modifica/eliminazione, manuali, documenti VO, directory SOS, comunicazioni, online e registro operazioni. Modalità chiara/scura. Nessuna demo.

## Dati mancanti

Storico pratiche/reclami, TEAM SOSPC e collegamenti documentali del foglio originale non sono importati. I due allegati contengono il codice, non le righe del foglio. Gli esportati originali sono necessari per un’importazione fedele e per assegnare tutti gli operatori ATPAY.

## Sviluppo e database

`npm ci`, `npm run dev`, `npm run typecheck`, `npm run build`. Variabili: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`. Nessuna chiave service-role nell’app Vercel. I cookie sono HttpOnly, Secure in produzione e SameSite=Lax; le scritture verificano la stessa origine.

`database/schema.sql` è la migrazione iniziale. I file successivi in `database/migrations` documentano gli aggiornamenti applicati; non rieseguirli sul progetto attuale. Le assegnazioni nominative degli amministratori sono state eseguite nel database e non pubblicate come directory nel sorgente.

# Portale ASO / ATPAY

Web app Next.js su Vercel, PostgreSQL e autenticazione Supabase. Tabelle private in `portal_internal` nel progetto condiviso con PT-PRO; nessuna modifica alle tabelle o alle policy dell’app PT-PRO. Nessun nuovo piano a pagamento.

## Flusso operativo originale

ASO187/191 sono origini dell’inserimento, non code indipendenti. Tutte le pratiche confluiscono nella coda comune BO ATPAY. Il back office prende la prima disponibile in ordine di creazione. Una pratica BO attiva per operatore; se già in carico viene mantenuta. Esiti, note, richiami con VO e orario italiano 08–22, rilascio differite al successivo aggiornamento nella finestra operativa.

Reclami: caricamento amministratore con una riga per reclamo; scelta esplicita dell’operatore; testo e note distinti; Gestito libera l’assegnazione e consente di riprendere; Chiusa elimina la riga e conserva l’evento di audit.

## Ruoli

Il proprietario preesistente ha il ruolo riservato `super_admin`: accesso completo e permesso Recuperi inclusi. Il suo account è escluso dalla lista utenti/ruoli anche nel payload server; la cronologia delle autorizzazioni mostra la dicitura Super Admin al posto della sua email. Il database impedisce di attribuire quel ruolo ad altri indirizzi, declassare o disattivare il proprietario dalla gestione utenti. Non esiste un’opzione Super Admin nel selettore dei ruoli.

- `inserimento`: inserisce e consulta soltanto i propri invii; non lavora pratiche né reclami. Vede quantità aggregata della coda e attesa stimata (8 minuti per pratica).
- `atpay`: inserisce, prende in carico dalla coda BO, aggiorna proprie lavorazioni, sceglie e lavora reclami; non vede archivio completo né gestione utenti.
- `recuperi`: sceglie fuori ordine le pratiche disponibili, acquisisce il VO e può chiuderle/differirle prima della presa in carico BO.
- `admin`: archivio completo BOOM, statistiche globali, reclami massivi, risorse, utenti e ruoli, messaggio globale e presenze.

I nove amministratori del codice originale sono stati abilitati nel database, separatamente dalla configurazione pubblica del repository. L’account proprietario preesistente resta amministratore. L’elenco TEAM SOSPC originale è stato importato dall’esportazione fornita dall’utente. La directory TEAM SOSPC ha le cinque colonne originali e un import tramite incolla-tabella. Le abilitazioni ATPAY si assegnano per email esatta nella gestione utenti.

## Registrazione

`/login` offre accesso, registrazione e recupero. Registrazione e ingresso al portale riservati a `@konecta.com`, salvo l’account proprietario già esistente. I nuovi account devono confermare l’email; il ruolo predefinito è Inserimento, non modificabile tramite metadata inviati dal browser. Il database verifica identità e ruolo a ogni operazione.

Prima dell’apertura a tutto il team verificare in Supabase Auth:

- Redirect URLs comprendenti `https://portale-pratiche.vercel.app/login` e `https://portale-pratiche.vercel.app/reset`, preservando quelle esistenti.
- Un servizio SMTP capace di inviare ai destinatari aziendali. L’invio reale e l’arrivo nelle caselle Konecta non sono stati collaudati dall’agente. Il servizio email predefinito Supabase ha restrizioni e limiti; non promettere onboarding illimitato senza questa verifica.

Non disabilitare la conferma email: gli amministratori sono individuati tramite indirizzi aziendali e la loro proprietà va verificata. Password e sessioni Auth sono condivise con l’infrastruttura esistente: il cambio password dello stesso account vale anche nelle altre app che lo usano. Il logout usa scope local.

## Altre funzioni ripristinate

Statistiche giorno/settimana/mese/tutto, produttività FK e rate orario, obiettivi dagli ultimi 30 giorni, trend, heatmap, fasce di traffico storico, attesa stimata, appunti personali persistenti, calendario personale nel browser, link sistemi con modifica/eliminazione, manuali, documenti VO, directory SOS, comunicazioni, online e registro operazioni. Modalità chiara/scura. Nessuna demo.

## Recuperi e Verbal Order

Pannello distinto per il ruolo `recuperi`; gli amministratori possono anche abilitare il permesso aggiuntivo `can_recover` a un altro ruolo. Nessuna abilitazione Recuperi deriva dalla sola registrazione o da metadata dichiarati dal browser.

Gli addetti scelgono manualmente una pratica Nuova non ancora assegnata al BO. L’assegnazione Recuperi è distinta da quella BO; non crea copie e non blocca la presa in carico FIFO. Il BO continua a selezionare la prima pratica per data di creazione, anche se ha un recupero VO in corso.

“Registra solo VO” salva esclusivamente il numero e la traccia dell’attività Recuperi, senza cambiare creazione, aggiornamento della lavorazione BO, stato, assegnazione BO o scadenza. Il codice può essere aggiunto anche se nel frattempo il BO prende la stessa pratica. La chiusura BO conserva il VO.

Chiusura con esito e Differita aggiornano la stessa pratica. Se il BO l’ha già presa, queste due operazioni sono rifiutate ai Recuperi per evitare sovrascritture; rimane possibile completare il VO. Le differite usano data futura e fascia italiana 08–22.

L’assegnazione Recuperi si libera con il salvataggio, il rilascio manuale, la conclusione BO o dopo 30 minuti senza aggiornamenti del portale dell’addetto. Ogni azione è registrata nell’audit della pratica. Non ci sono utenti abilitati automaticamente: l’amministratore assegna il ruolo o il permesso dalla gestione utenti.

## Gestione nuovi operatori

Gli utenti si registrano con email aziendale verificata e ruolo Inserimento. Possono inviare una richiesta di accesso BO con matricola/codice e motivazione. Solo un amministratore può approvarla o rifiutarla. Un codice dichiarato non concede mai permessi automaticamente.

Gli amministratori possono aggiungere e modificare l’anagrafica TEAM SOSPC, associare un’email aziendale esplicita e abilitare/disabilitare la lavorazione BO. Gli account possono essere disattivati dalla gestione utenti. Permessi e decisioni sono registrati nella cronologia delle autorizzazioni. Non serve mantenere un Excel per i nuovi inserimenti.

## Importazione iniziale

Importati nel database l’anagrafica di 30 operatori, 35 risorse e 34 eventi del registro originale. Quattro anagrafiche utente sono state riportate come abilitazioni; i ruoli amministratore già assegnati sono stati preservati. Le email BO sono state associate solo quando presenti nel file e riconducibili in modo univoco alla directory; per le altre righe l’email resta da associare nell’app.

Il file caricato aveva Pratiche, Reclami e Storico vuoti. Cinque risorse erano prive di URL e rimangono marcate come da completare. Il registro conserva anche l’ID originale della pratica, senza inventare pratiche mancanti. Password, salt, hash e token del vecchio foglio Utenti non sono importati né pubblicati: gli utenti aziendali si registrano/confermano con il sistema Auth.

Il file sorgente e i dati individuali dell’importazione non sono inclusi nel repository pubblico. Le tabelle si gestiscono ora dall’app; l’Excel ha fornito soltanto la situazione iniziale.

## Sviluppo e database

`npm ci`, `npm run dev`, `npm run typecheck`, `npm run build`. Variabili: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`. Nessuna chiave service-role nell’app Vercel. I cookie sono HttpOnly, Secure in produzione e SameSite=Lax; le scritture verificano la stessa origine.

`database/schema.sql` è la migrazione iniziale. I file successivi in `database/migrations` documentano gli aggiornamenti applicati; non rieseguirli sul progetto attuale. Le assegnazioni nominative degli amministratori sono state eseguite nel database e non pubblicate come directory nel sorgente.

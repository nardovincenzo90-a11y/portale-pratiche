# Portale Pratiche — GitHub + Vercel

Applicazione Next.js autonoma per Vercel. Il database Supabase dedicato è in attesa di attivazione: l’organizzazione ha raggiunto il limite di progetti gratuiti. Fino alla configurazione, login e archivio non sono operativi.

## Architettura

Next.js su Vercel, sorgente su GitHub, Supabase dedicato per PostgreSQL e autenticazione email/password. Nessuna dipendenza da Google Sheets o dall’autenticazione ChatGPT. Nessun dato o chiave reale incluso.

## Attivazione

1. Repository: `nardovincenzo90-a11y/portale-pratiche`. Il repository creato dall’utente è pubblico; contiene esclusivamente codice, schema e configurazione di esempio. Credenziali e dati reali devono restare esclusi.
2. Creare un progetto Supabase dedicato nell’organizzazione scelta dall’utente e verificare il costo prima di attivare risorse a pagamento.
3. Applicare `database/schema.sql` una sola volta al nuovo database e verificare i security advisor. Le tabelle sono chiuse ad accesso diretto da browser; le operazioni passano dal server con una chiave segreta. Le funzioni sono eseguibili soltanto da `service_role`.
4. Creare l’account iniziale tramite Supabase Auth e inserire il relativo indirizzo email in `portal_members` con ruolo `admin`. Nessuna promozione automatica del primo visitatore.
5. Disattivare le iscrizioni pubbliche e configurare le email Auth. L’abilitazione nel Team non crea da sola un account Auth: anche gli operatori devono ricevere un account dalla console Supabase. Il recupero password self-service e l’invito integrato non sono implementati in questa versione.
6. Importare il repository in Vercel come Next.js, regione fra1. Configurare `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` tra le variabili d’ambiente, senza scriverle nel codice. Non usare prefissi NEXT_PUBLIC per chiavi segrete.
7. Eseguire typecheck e build, poi collaudare login, logout, rinnovo sessione, presa in carico concorrente con due operatori, permessi e persistenza. Testare tutte le operazioni sul database dedicato prima dell’utilizzo reale.

## Note operative

- Le sessioni usano cookie HttpOnly, Secure in produzione e SameSite=Lax. L’identità viene verificata tramite Auth; il ruolo è letto nel database a ogni operazione. Non si usano intestazioni identità fornite dal browser.
- Un operatore può vedere le pratiche create da lui, assegnate a lui e quelle disponibili. Può aggiornare le assegnate a lui. L’amministratore vede e gestisce tutto.
- La presa in carico e gli aggiornamenti con il relativo storico sono transazioni PostgreSQL. Il vincolo univoco impedisce più pratiche contemporaneamente in lavorazione per lo stesso operatore.
- Le differite tornano in coda al successivo caricamento/aggiornamento del portale dopo la scadenza; non esiste ancora un processo pianificato a portale chiuso.
- Il CSV esporta le righe visibili dopo i filtri. Nessun import dello storico presente.
- Le statistiche riguardano tutto l’archivio visibile; non ci sono ancora filtri giornalieri, settimanali o mensili.
- I materiali sono collegamenti HTTPS; non esiste upload di file.
- Non sono presenti notifiche push, messaggistica, calendario, presenze online, SLA, obiettivi o previsioni di traffico.
- La build senza configurazione non abilita un archivio dimostrativo pubblico: l’API rimane chiusa.

Il file `database/schema.sql` è una bozza di attivazione da verificare su un database nuovo; non è stato applicato ai database PT-PRO o ASD ABC Cosenza.

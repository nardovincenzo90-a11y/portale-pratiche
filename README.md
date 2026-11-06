# Portale Pratiche

Applicazione Next.js su Vercel con PostgreSQL e autenticazione Supabase. Non dipende da Google Sheets.

## Infrastruttura attuale

Il portale usa lo schema riservato `portal_internal` nel progetto Supabase esistente di PT-PRO. I dati e le autorizzazioni del portale sono distinti; risorse e limiti del piano gratuito sono condivisi. Tabelle, policy, dati e configurazione Auth dell’app PT-PRO non sono stati cambiati. L’identità Auth è condivisa: gli utenti devono avere un account Supabase verificato e l’abilitazione in `portal_members`.

Le operazioni applicative passano dalle funzioni `public.portal_snapshot` e `public.portal_mutate`. Queste chiamano funzioni interne che verificano l’identità tramite `auth.uid()` e il ruolo tramite `portal_members`. L’accesso diretto alle tabelle è negato ad anon e authenticated. Le chiavi privilegiate di progetto non sono utilizzate dal portale.

## Sviluppo

`npm ci`, poi `npm run dev`. Per validare: `npm run typecheck` e `npm run build`.

Variabili su Vercel: `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`. I token utente sono contenuti in cookie HttpOnly, Secure in produzione, SameSite=Lax. Il logout è locale alla sessione del portale. Nessuna chiave segreta o dato cliente nel repository.

`database/schema.sql` documenta la migrazione iniziale già applicata. Non eseguirla di nuovo sul progetto esistente. Le modifiche successive devono usare migrazioni incrementali.

## Funzioni

Pratiche ASO187/191, BO ATPAY e reclami; inserimento, priorità, coda, una lavorazione attiva per operatore, esiti e note, differite, ricerca e filtri, esportazione CSV, statistiche, collegamenti documentali, gestione delle abilitazioni e registro attività. Tema chiaro/scuro. Nessuna modalità demo.

Gli operatori vedono le proprie pratiche e la coda; possono aggiornare soltanto quelle assegnate a loro. L’amministratore vede tutto. L’abilitazione dal Team non crea automaticamente un account Auth: le altre persone devono avere prima un account verificato nel sistema di autenticazione condiviso.

## Limiti attuali

- Storico Google Sheets non importato.
- Differite rilasciate al successivo aggiornamento del portale; nessuna esecuzione programmata a portale chiuso.
- Nessun caricamento massivo, recupero password self-service, invito account integrato, messaggistica, calendario, presenze online, notifiche push o upload di file.
- Statistiche sull’archivio visibile, senza filtri di periodo.
- Nessuna garanzia di risorse illimitate: utilizzo e quote vanno monitorati prima dell’estensione a tutto il team.

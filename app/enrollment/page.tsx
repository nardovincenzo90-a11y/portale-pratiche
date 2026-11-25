'use client';

import { useEffect, useState } from 'react';

type Enrollment = {
  id: string;
  name: string;
  work_email: string;
  recovery_email: string;
  approved_at: string | null;
};

export default function Enrollments() {
  const [requests, setRequests] = useState<Enrollment[]>([]);
  const [message, setMessage] = useState('Caricamento…');
  const [busy, setBusy] = useState(false);

  async function load() {
    const response = await fetch('/api/enrollment', { cache: 'no-store' });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);
    setRequests(data.requests);
  }

  useEffect(() => {
    load().then(() => setMessage('')).catch(error => setMessage(error.message));
  }, []);

  async function approve(request: Enrollment) {
    if (!window.confirm('Hai verificato tramite un canale aziendale che ' + request.work_email + ' appartenga a questa persona e che la casella alternativa sia corretta?')) return;
    setBusy(true);
    try {
      const response = await fetch('/api/enrollment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: request.id }),
      });
      const data = await response.json();
      setMessage(data.message || data.error);
      await load();
    } catch {
      setMessage('Operazione non completata. Ricarica la pagina.');
    } finally {
      setBusy(false);
    }
  }

  return <main style={{ margin: '2rem auto', padding: '1rem', maxWidth: 1000 }}>
    <a className="subtle" href="/">← Portale</a>
    <section className="panel spaced">
      <h1>Richieste di iscrizione</h1>
      <p>Verifica il titolare dell’account Konecta e l’indirizzo alternativo tramite un canale aziendale già noto prima di approvare.</p>
      {message && <p role="status">{message}</p>}
      {!requests.length && !message && <p>Nessuna richiesta.</p>}
      <ul>{requests.map(request => <li className="channel" key={request.id}>
        <div><b>{request.name}</b><small>{request.work_email}</small><small>Attivazione e recupero: {request.recovery_email}</small></div>
        <button className="primary" disabled={busy} onClick={() => approve(request)}>
          {request.approved_at ? 'Reinvia attivazione' : 'Approva e invia attivazione'}
        </button>
      </li>)}</ul>
    </section>
  </main>;
}

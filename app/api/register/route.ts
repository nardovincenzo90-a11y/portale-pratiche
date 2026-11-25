import { sameOrigin } from '../../../lib/backend';
import { companyEmail, validEmail, enrollmentService } from '../../../lib/enrollment';

export async function POST(req: Request) {
  if (!sameOrigin(req)) return Response.json({ error: 'Origine non valida.' }, { status: 403 });
  try {
    const body = await req.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const alternate = String(body.recovery_email ?? '').trim().toLowerCase();
    const name = String(body.name ?? '').trim();
    if (!companyEmail.test(email) || email.length > 254) {
      return Response.json({ error: 'Inserisci il tuo indirizzo @konecta.com.' }, { status: 400 });
    }
    if (!validEmail.test(alternate) || alternate.length > 254 || companyEmail.test(alternate)) {
      return Response.json({ error: 'Inserisci un indirizzo alternativo che puoi consultare.' }, { status: 400 });
    }
    if (!name || name.length > 120) return Response.json({ error: 'Inserisci nome e cognome.' }, { status: 400 });
    await enrollmentService('request', { work_email: email, recovery_email: alternate, name });
    return Response.json({ message: 'Richiesta ricevuta. Dopo la verifica dell’amministratore, riceverai il link di attivazione sulla casella alternativa indicata.' });
  } catch {
    return Response.json({ error: 'Registrazione temporaneamente non disponibile.' }, { status: 503 });
  }
}

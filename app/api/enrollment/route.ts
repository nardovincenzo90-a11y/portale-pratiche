import { currentUser, rpc, sameOrigin } from '../../../lib/backend';
import { sendEnrollmentLink } from '../../../lib/enrollment';

export async function GET() {
  try {
    const user = await currentUser();
    if (!user) return Response.json({ error: 'Accedi come amministratore.' }, { status: 401 });
    const requests = await rpc('portal_enrollment_admin', {}, user.accessToken);
    return Response.json({ requests }, { headers: { 'Cache-Control': 'no-store' } });
  } catch {
    return Response.json({ error: 'Elenco riservato agli amministratori o servizio non disponibile.' }, { status: 403 });
  }
}

export async function POST(req: Request) {
  if (!sameOrigin(req)) return Response.json({ error: 'Origine non valida.' }, { status: 403 });
  try {
    const user = await currentUser();
    if (!user) return Response.json({ error: 'Accedi come amministratore.' }, { status: 401 });
    const { id } = await req.json();
    if (typeof id !== 'string' || !/^[a-f\d-]{36}$/i.test(id)) {
      return Response.json({ error: 'Richiesta non valida.' }, { status: 400 });
    }
    const request = await rpc('portal_enrollment_admin', { request_id: id }, user.accessToken);
    const sent = await sendEnrollmentLink(request.work_email, true);
    return Response.json({
      message: sent ? 'Abbinamento approvato. Invio accettato dal servizio email.' :
        'Invio non avviato. Attendi due minuti prima di riprovare. Controlla che l’account sia attivo.',
    });
  } catch {
    return Response.json({ error: 'Operazione incompleta. Aggiorna l’elenco prima di riprovare.' }, { status: 400 });
  }
}

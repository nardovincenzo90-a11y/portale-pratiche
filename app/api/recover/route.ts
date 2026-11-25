import { authRequest, sameOrigin } from '../../../lib/backend';
import { companyEmail, recoveryNotice, sendEnrollmentLink } from '../../../lib/enrollment';

export async function POST(req: Request) {
  if (!sameOrigin(req)) return Response.json({ error: 'Origine non valida.' }, { status: 403 });
  try {
    const body = await req.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    if (email === 'nardovincenzo90@gmail.com') {
      await authRequest('recover?redirect_to=' + encodeURIComponent('https://portale-pratiche.vercel.app/reset'), { email });
    } else if (companyEmail.test(email) && email.length <= 254) {
      await sendEnrollmentLink(email, false).catch(() => console.warn('Invio recupero Portale non completato'));
    } else {
      return Response.json({ error: 'Inserisci il tuo indirizzo @konecta.com.' }, { status: 400 });
    }
    return Response.json({ message: recoveryNotice });
  } catch {
    return Response.json({ error: 'Recupero temporaneamente non disponibile.' }, { status: 503 });
  }
}

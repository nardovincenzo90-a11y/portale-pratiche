import { config } from './backend';

export const companyEmail = /^[^\s@]+@konecta\.com$/;
export const validEmail = /^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$/;
export const recoveryNotice =
  'Se la richiesta è valida, il link arriverà all’indirizzo email alternativo indicato alla registrazione. Controlla anche la posta indesiderata.';

function credentials() {
  const key = process.env.PORTAL_SUPABASE_ADMIN_KEY;
  const mailKey = process.env.PORTAL_BREVO_API_KEY;
  const sender = process.env.PORTAL_MAIL_SENDER || 'nardovincenzo90@gmail.com';
  if (!key || !mailKey || !sender) throw new Error('Invio email da configurare');
  return { key, mailKey, sender };
}

export async function enrollmentService(operation: string, details: Record<string, string>) {
  const { key } = credentials();
  const { url } = config();
  const response = await fetch(url + '/rest/v1/rpc/portal_enrollment_service', {
    method: 'POST',
    headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
    body: JSON.stringify({ operation, details }),
    cache: 'no-store',
  });
  if (!response.ok) throw new Error('Servizio iscrizioni non disponibile');
  return response.json();
}

export async function sendEnrollmentLink(workEmail: string, activate: boolean, alternate?: string) {
  const { key, mailKey, sender } = credentials();
  const enrollment = await enrollmentService('reserve_send', { work_email: workEmail, ...(alternate ? { recovery_email: alternate } : {}) });
  if (!enrollment) return false;

  const { url } = config();
  const response = await fetch(url + '/auth/v1/admin/generate_link', {
    method: 'POST',
    headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      type: activate ? 'magiclink' : 'recovery',
      email: workEmail,
      data: { name: enrollment.name },
      redirect_to: 'https://portale-pratiche.vercel.app/reset',
    }),
  });
  if (!response.ok) throw new Error('Link non disponibile');
  const { action_link: link } = await response.json();
  if (typeof link !== 'string' || new URL(link).origin !== new URL(url).origin) {
    throw new Error('Link non valido');
  }
  const sent = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': mailKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      sender: { email: sender, name: 'Portale Pratiche' },
      to: [{ email: enrollment.recovery_email }],
      subject: activate ? 'Attiva il tuo account Portale Pratiche' : 'Recupero password Portale Pratiche',
      textContent: 'Account di lavoro: ' + workEmail + '\n\nApri questo link e imposta la password del portale:\n' + link,
    }),
  });
  if (!sent.ok) throw new Error('Invio non accettato');
  return true;
}

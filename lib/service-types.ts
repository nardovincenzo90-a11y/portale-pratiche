export const serviceRequests = [
  'CARING',
  'SWAP LIGHT DECODER',
  'SWAP LIGHT MODEM',
  'ONSITE',
  'VENDITA PRODOTTO',
] as const;

export const serviceOutcomes = [
  'Fatturato Caring',
  'Swap Light',
  'Onsite a pagamento',
  'ONSITE 191',
  'ONSITE 187',
  'Vendita prodotto',
] as const;

export function matchesService(row: { requested_service?: string | null; status: string }, filter: string) {
  const service = row.requested_service;
  if (filter === 'all') {
    return serviceRequests.some(request => request === service)
      || (!service && serviceOutcomes.some(outcome => outcome === row.status));
  }
  if (service === filter) return true;
  if (filter === 'SWAP LIGHT') {
    return service === 'SWAP LIGHT DECODER' || service === 'SWAP LIGHT MODEM' || (!service && row.status === 'Swap Light');
  }
  if (service) return false;
  return (filter === 'CARING' && row.status === 'Fatturato Caring')
    || (filter === 'ONSITE' && ['Onsite a pagamento','ONSITE 191','ONSITE 187'].includes(row.status))
    || (filter === 'VENDITA PRODOTTO' && row.status === 'Vendita prodotto');
}

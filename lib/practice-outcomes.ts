export const closingOutcomes = [
  'FK15', 'FK30', 'FK03', 'Fatturato Caring', 'Swap Light', 'Vendita prodotto',
  'Rifiuto', 'Nongestibile', 'Improprio', 'NON RISPONDE', 'ONSITE 191',
  'ONSITE 187', 'RISOLTO CLIENTE', 'Aprire segnalazione tecnica',
];

export const historicalOutcomes = [
  'Onsite a pagamento', 'In carico altro operatore',
  'Messa in 115', 'Chiusa non fatturata',
];

export function outcomeLabel(outcome: string) {
  return outcome === 'Nongestibile' ? 'NON GESTIBILE' : outcome.toUpperCase();
}

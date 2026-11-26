'use client';

import { useEffect, useState } from 'react';
import { romeDay } from '../lib/dates';

type Shift = { start: string; end: string; off: boolean };
const emptyShift: Shift = { start: '', end: '', off: false };
const romeTime = new Intl.DateTimeFormat('it-IT', {
  timeZone: 'Europe/Rome', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
});

function dayAfter(day: string) {
  const date = new Date(day + 'T12:00:00Z');
  date.setUTCDate(date.getUTCDate() + 1);
  return date.toISOString().slice(0, 10);
}

export default function DeferredRecallFields({ email, vo }: { email: string; vo?: string | null }) {
  const today = romeDay(new Date().toISOString());
  const tomorrow = dayAfter(today);
  const [choice, setChoice] = useState<'today' | 'tomorrow' | 'other'>('today');
  const [otherDay, setOtherDay] = useState('');
  const [time, setTime] = useState('');
  const [shifts, setShifts] = useState<Record<string, Shift>>({});
  const [feedback, setFeedback] = useState('');
  const day = choice === 'today' ? today : choice === 'tomorrow' ? tomorrow : otherDay;
  const shift = shifts[day] ?? emptyShift;
  const storageKey = 'portal-bo-shifts:' + email;

  useEffect(() => {
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey) || '{}');
      if (saved && typeof saved === 'object') setShifts(saved);
    } catch {}
  }, [storageKey]);

  function updateShift(next: Shift) {
    if (!day) return;
    const updated = { ...shifts, [day]: next };
    setShifts(updated);
    try {
      localStorage.setItem(storageKey, JSON.stringify(Object.fromEntries(
        Object.entries(updated).filter(([date]) => date >= today)
      )));
    } catch {}
  }

  function quickTime(minutes: number) {
    const target = new Date(Date.now() + minutes * 60_000);
    const targetDay = romeDay(target.toISOString());
    const targetTime = romeTime.format(target);
    if (targetTime < '08:00' || targetTime > '22:00') {
      setFeedback('La scorciatoia supera la fascia dei richiami. Scegli giorno e ora.');
      return;
    }
    setChoice(targetDay === today ? 'today' : 'tomorrow');
    setTime(targetTime);
    setFeedback('');
  }

  const validShift = shift.start && shift.end && shift.start < shift.end;
  const validTime = day && time >= '08:00' && time <= '22:00';
  const personal = validShift && time >= shift.start && time < shift.end;

  return <>
    <div role="group" aria-label="Giorno del richiamo" className="toolbar">
      {([['today', 'Oggi'], ['tomorrow', 'Domani'], ['other', 'Altra data']] as const).map(([value, label]) =>
        <button type="button" key={value} className={choice === value ? 'primary' : 'subtle'}
          aria-pressed={choice === value} onClick={() => { setChoice(value); setFeedback(''); }}>{label}</button>)}
    </div>
    {choice === 'other' && <label>Data del richiamo
      <input type="date" required min={today} value={otherDay} onChange={event => setOtherDay(event.target.value)} />
    </label>}
    <div className="formgrid">
      <label>Ora del richiamo
        <input type="time" required min="08:00" max="22:00" value={time}
          onChange={event => { setTime(event.target.value); setFeedback(''); }} />
      </label>
      <label>Codice VO<input name="vo" defaultValue={vo || ''} required pattern="[0-9]+" /></label>
    </div>
    <div className="toolbar">
      <button type="button" className="subtle" onClick={() => quickTime(30)}>+30 min</button>
      <button type="button" className="subtle" onClick={() => quickTime(60)}>+1 ora</button>
      <button type="button" className={shift.off ? 'primary' : 'subtle'} aria-pressed={shift.off} disabled={!day}
        onClick={() => updateShift({ ...shift, off: !shift.off })}>Non sono in turno</button>
    </div>
    {!shift.off && <div className="formgrid">
      <label>Inizio turno<input type="time" required disabled={!day} value={shift.start}
        onChange={event => updateShift({ ...shift, start: event.target.value })} /></label>
      <label>Fine turno<input type="time" required disabled={!day} value={shift.end}
        onChange={event => updateShift({ ...shift, end: event.target.value })} /></label>
    </div>}
    <input type="hidden" name="due" value={day && time ? day + 'T' + time : ''} />
    {shift.off ? <input type="hidden" name="shift_off" value="true" /> : <>
      <input type="hidden" name="shift_start" value={day && shift.start ? day + 'T' + shift.start : ''} />
      <input type="hidden" name="shift_end" value={day && shift.end ? day + 'T' + shift.end : ''} />
    </>}
    <p className="muted">Ora italiana. Il turno resta memorizzato su questo browser per il giorno scelto.</p>
    {feedback && <p role="status">{feedback}</p>}
    {validTime && (shift.off || validShift) && <p className="banner" role="status">
      {!shift.off && personal ? 'Torna a te alle ' + time : 'Va in coda comune alle ' + time}
    </p>}
  </>;
}

'use client';

import {useRef, useState} from 'react';

export default function Recorder() {
  const recorder = useRef<MediaRecorder | null>(null);
  const [microphone, setMicrophone] = useState(false);
  const [status, setStatus] = useState('');
  const [recording, setRecording] = useState(false);
  const [starting, setStarting] = useState(false);

  async function start() {
    if (!navigator.mediaDevices?.getDisplayMedia || !window.MediaRecorder) {
      setStatus('Usa il registratore del computer per catturare questa scheda.');
      return;
    }
    setStarting(true);
    let screen: MediaStream | undefined;
    let voice: MediaStream | undefined;
    try {
      screen = await navigator.mediaDevices.getDisplayMedia({video: true, audio: false});
      if (microphone) {
        voice = await navigator.mediaDevices.getUserMedia({audio: true});
        voice.getAudioTracks().forEach(track => screen?.addTrack(track));
      }
      const displayTrack = screen.getVideoTracks()[0];
      if (displayTrack.readyState !== 'live') throw new Error('Schermo non condiviso');
      const media = new MediaRecorder(screen);
      const chunks: Blob[] = [];
      recorder.current = media;
      media.ondataavailable = event => {
        if (event.data.size) chunks.push(event.data);
      };
      media.onstop = () => {
        screen?.getTracks().forEach(track => track.stop());
        recorder.current = null;
        setRecording(false);
        if (!chunks.length) {
          setStatus('Nessun video acquisito.');
          return;
        }
        const url = URL.createObjectURL(new Blob(chunks, {type: media.mimeType}));
        const link = document.createElement('a');
        link.href = url;
        link.download = 'Videocorso-BO-ATPAY.' + (media.mimeType.includes('mp4') ? 'mp4' : 'webm');
        link.click();
        window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
        setStatus('Video scaricato.');
      };
      displayTrack.onended = () => {
        if (media.state !== 'inactive') media.stop();
      };
      media.start(1000);
      setRecording(true);
      setStatus('Registrazione in corso');
    } catch {
      screen?.getTracks().forEach(track => track.stop());
      voice?.getTracks().forEach(track => track.stop());
      recorder.current = null;
      setStatus('Registrazione non avviata. Controlla i permessi del browser.');
    } finally {
      setStarting(false);
    }
  }

  return <>
    {!recording && <label><input type="checkbox" checked={microphone} onChange={event => setMicrophone(event.target.checked)} /> Microfono</label>}
    {recording
      ? <button onClick={() => { if (recorder.current?.state === 'recording') recorder.current.stop(); }}>Ferma e scarica</button>
      : <button disabled={starting} onClick={start}>Registra schermo</button>}
    {status && <small role="status">{status}</small>}
  </>;
}

'use strict';

(() => {
  const config = window.clientConfig;
  const elements = {
    user: document.querySelector('#sip-user'),
    password: document.querySelector('#sip-password'),
    domain: document.querySelector('#sip-domain'),
    target: document.querySelector('#call-target'),
    registrationStatus: document.querySelector('#registration-status'),
    callStatus: document.querySelector('#call-status'),
    register: document.querySelector('#register-button'),
    unregister: document.querySelector('#unregister-button'),
    call: document.querySelector('#call-button'),
    answer: document.querySelector('#answer-button'),
    reject: document.querySelector('#reject-button'),
    hangup: document.querySelector('#hangup-button'),
    remoteAudio: document.querySelector('#remote-audio'),
    log: document.querySelector('#event-log'),
    clearLog: document.querySelector('#clear-log-button')
  };

  let userAgent = null;
  let activeSession = null;
  let localMediaStream = null;
  let teardownTimer = null;

  elements.user.value = config.defaultSipUser;
  elements.target.value = config.defaultPeerUser;
  elements.domain.textContent = config.sipDomain;
  elements.remoteAudio.addEventListener('playing', () => appendLog('Remote audio playback started'));

  function appendLog(message) {
    const item = document.createElement('li');
    const time = new Date().toLocaleTimeString();
    item.textContent = `${time}  ${message}`;
    elements.log.prepend(item);
  }

  function setStatus(element, text, kind = 'idle') {
    element.textContent = text;
    element.className = `status ${kind}`;
  }

  function setRegistered(registered) {
    elements.register.disabled = registered;
    elements.unregister.disabled = !registered;
    elements.call.disabled = !registered || Boolean(activeSession);
  }

  function releaseLocalMedia() {
    if (!localMediaStream) return;
    localMediaStream.getTracks().forEach((track) => track.stop());
    localMediaStream = null;
  }

  function setSession(session, incoming = false) {
    if (!session && teardownTimer) {
      window.clearTimeout(teardownTimer);
      teardownTimer = null;
    }
    activeSession = session;
    const active = Boolean(session);
    elements.call.disabled = !userAgent?.isRegistered() || active;
    elements.hangup.disabled = !active;
    elements.answer.disabled = !incoming;
    elements.reject.disabled = !incoming;
    if (!active) {
      releaseLocalMedia();
      setStatus(elements.callStatus, 'Idle');
      elements.remoteAudio.srcObject = null;
    }
  }

  function attachSession(session, incoming) {
    setSession(session, incoming);
    setStatus(elements.callStatus, incoming ? 'Incoming' : 'Calling', 'pending');
    appendLog(incoming ? `Incoming call from ${session.remote_identity.uri}` : 'Outgoing call started');

    session.on('peerconnection', ({ peerconnection }) => {
      peerconnection.addEventListener('track', (event) => {
        const stream = event.streams[0] || new MediaStream([event.track]);
        elements.remoteAudio.srcObject = stream;
        elements.remoteAudio.muted = false;
        elements.remoteAudio.volume = 1;
        appendLog(`Remote ${event.track.kind} track received`);
        event.track.addEventListener('unmute', () => appendLog('Remote audio packets received'), { once: true });
        elements.remoteAudio.play().catch(() => appendLog('Remote audio is ready; press Play in the audio controls'));
      });
    });
    session.on('progress', () => setStatus(elements.callStatus, 'Ringing', 'pending'));
    session.on('accepted', () => setStatus(elements.callStatus, 'Connecting', 'pending'));
    session.on('confirmed', () => {
      setStatus(elements.callStatus, 'Connected', 'online');
      elements.answer.disabled = true;
      elements.reject.disabled = true;
      appendLog('Call connected');
      elements.remoteAudio.play().catch(() => appendLog('Press Play in the audio controls to hear the call'));
    });
    const finish = (event) => {
      appendLog(`Call finished: ${event.cause || 'ended'}`);
      if (activeSession === session) setSession(null);
    };
    session.on('ended', finish);
    session.on('failed', finish);
  }

  function terminateActiveSession() {
    const session = activeSession;
    if (!session) {
      appendLog('No active call to hang up');
      setSession(null);
      return;
    }

    elements.hangup.disabled = true;
    elements.answer.disabled = true;
    elements.reject.disabled = true;
    setStatus(elements.callStatus, 'Ending', 'pending');
    appendLog('Ending call');

    teardownTimer = window.setTimeout(() => {
      teardownTimer = null;
      if (activeSession !== session) return;
      appendLog('Call ended locally after teardown timeout');
      setSession(null);
    }, 5000);

    try {
      session.terminate();
    } catch (error) {
      appendLog(`Hang up failed: ${error?.message || 'unknown error'}`);
      if (activeSession === session) setSession(null);
      return;
    }
  }

  function mediaErrorMessage(error) {
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
      return 'Microphone access requires a supported browser and trusted HTTPS connection';
    }
    if (error?.name === 'NotAllowedError') {
      return "Microphone blocked. Allow microphone access in this site's settings and in your operating system, then retry";
    }
    if (error?.name === 'NotFoundError') {
      return 'No microphone was found. Connect or enable an audio input device, then retry';
    }
    if (error?.name === 'NotReadableError') {
      return 'Microphone is unavailable. Close other apps using it, then retry';
    }
    return `Microphone access failed: ${error?.message || 'unknown error'}`;
  }

  async function mediaOptions() {
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
      throw new DOMException('Microphone capture is unavailable', 'NotSupportedError');
    }
    localMediaStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
    return {
      mediaStream: localMediaStream,
      pcConfig: { iceServers: config.iceServers }
    };
  }

  function handleMediaError(error, incoming = false) {
    releaseLocalMedia();
    setStatus(elements.callStatus, 'Microphone blocked', 'error');
    appendLog(mediaErrorMessage(error));
    elements.call.disabled = !userAgent?.isRegistered() || Boolean(activeSession);
    elements.answer.disabled = !incoming;
    elements.reject.disabled = !incoming;
  }

  elements.register.addEventListener('click', () => {
    const username = elements.user.value.trim();
    const password = elements.password.value;
    if (!username || !password) {
      appendLog('SIP user and password are required');
      return;
    }

    const socket = new JsSIP.WebSocketInterface(config.webSocketUri);
    userAgent = new JsSIP.UA({
      sockets: [socket],
      uri: `sip:${username}@${config.sipDomain}`,
      password,
      register: true,
      session_timers: false
    });
    userAgent.on('connecting', () => setStatus(elements.registrationStatus, 'Connecting', 'pending'));
    userAgent.on('connected', () => appendLog('Secure WebSocket connected'));
    userAgent.on('disconnected', () => {
      setStatus(elements.registrationStatus, 'Offline');
      setRegistered(false);
      appendLog('WebSocket disconnected');
    });
    userAgent.on('registered', () => {
      setStatus(elements.registrationStatus, 'Registered', 'online');
      setRegistered(true);
      appendLog(`Registered sip:${username}@${config.sipDomain}`);
    });
    userAgent.on('registrationFailed', ({ cause }) => {
      setStatus(elements.registrationStatus, 'Failed', 'error');
      setRegistered(false);
      appendLog(`Registration failed: ${cause}`);
    });
    userAgent.on('newRTCSession', ({ originator, session }) => {
      if (activeSession && activeSession !== session) {
        session.terminate({ status_code: 486, reason_phrase: 'Busy Here' });
        return;
      }
      attachSession(session, originator === 'remote');
    });
    userAgent.start();
  });

  elements.unregister.addEventListener('click', () => {
    if (activeSession) activeSession.terminate();
    userAgent?.stop();
    userAgent = null;
    setSession(null);
    setRegistered(false);
    setStatus(elements.registrationStatus, 'Offline');
  });

  elements.call.addEventListener('click', async () => {
    const rawTarget = elements.target.value.trim();
    if (!rawTarget || !userAgent?.isRegistered()) return;
    const target = rawTarget.includes('@') ? rawTarget : `${rawTarget}@${config.sipDomain}`;
    elements.call.disabled = true;
    setStatus(elements.callStatus, 'Requesting microphone', 'pending');
    try {
      const options = await mediaOptions();
      userAgent.call(`sip:${target.replace(/^sip:/, '')}`, options);
    } catch (error) {
      handleMediaError(error);
    }
  });
  elements.answer.addEventListener('click', async () => {
    if (!activeSession) return;
    elements.answer.disabled = true;
    elements.reject.disabled = true;
    setStatus(elements.callStatus, 'Requesting microphone', 'pending');
    try {
      const options = await mediaOptions();
      activeSession.answer(options);
    } catch (error) {
      handleMediaError(error, true);
    }
  });
  elements.reject.addEventListener('click', () => activeSession?.terminate({ status_code: 486 }));
  elements.hangup.addEventListener('click', terminateActiveSession);
  elements.clearLog.addEventListener('click', () => elements.log.replaceChildren());
})();

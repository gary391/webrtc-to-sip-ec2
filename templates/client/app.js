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

  elements.user.value = config.defaultSipUser;
  elements.target.value = config.defaultPeerUser;
  elements.domain.textContent = config.sipDomain;

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

  function setSession(session, incoming = false) {
    activeSession = session;
    const active = Boolean(session);
    elements.call.disabled = !userAgent?.isRegistered() || active;
    elements.hangup.disabled = !active;
    elements.answer.disabled = !incoming;
    elements.reject.disabled = !incoming;
    if (!active) {
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
        const [stream] = event.streams;
        if (stream) {
          elements.remoteAudio.srcObject = stream;
          elements.remoteAudio.play().catch(() => appendLog('Use the page controls to allow audio playback'));
        }
      });
    });
    session.on('progress', () => setStatus(elements.callStatus, 'Ringing', 'pending'));
    session.on('accepted', () => setStatus(elements.callStatus, 'Connecting', 'pending'));
    session.on('confirmed', () => {
      setStatus(elements.callStatus, 'Connected', 'online');
      elements.answer.disabled = true;
      elements.reject.disabled = true;
      appendLog('Call connected');
    });
    const finish = (event) => {
      appendLog(`Call finished: ${event.cause || 'ended'}`);
      if (activeSession === session) setSession(null);
    };
    session.on('ended', finish);
    session.on('failed', finish);
  }

  function mediaOptions() {
    return {
      mediaConstraints: { audio: true, video: false },
      pcConfig: { iceServers: config.iceServers }
    };
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

  elements.call.addEventListener('click', () => {
    const rawTarget = elements.target.value.trim();
    if (!rawTarget || !userAgent?.isRegistered()) return;
    const target = rawTarget.includes('@') ? rawTarget : `${rawTarget}@${config.sipDomain}`;
    userAgent.call(`sip:${target.replace(/^sip:/, '')}`, mediaOptions());
  });
  elements.answer.addEventListener('click', () => {
    activeSession?.answer(mediaOptions());
    elements.answer.disabled = true;
    elements.reject.disabled = true;
  });
  elements.reject.addEventListener('click', () => activeSession?.terminate({ status_code: 486 }));
  elements.hangup.addEventListener('click', () => activeSession?.terminate());
  elements.clearLog.addEventListener('click', () => elements.log.replaceChildren());
})();

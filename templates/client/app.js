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
  let rtcStatsTimer = null;
  let previousRtcStats = null;
  let previousRtcPath = null;
  let rtcStatsSequence = 0;
  let rtcStatsCallId = 'unknown';
  let webSocketTicket = null;

  window.setWebSocketTicket = (ticket) => {
    webSocketTicket = String(ticket || '').trim() || null;
  };

  elements.user.value = config.defaultSipUser;
  elements.target.value = config.defaultPeerUser;
  elements.domain.textContent = config.sipDomain;
  elements.remoteAudio.autoplay = true;
  elements.remoteAudio.playsInline = true;
  elements.remoteAudio.preload = 'auto';
  elements.remoteAudio.addEventListener('playing', () => appendLog('Remote audio playback started'));
  elements.remoteAudio.addEventListener('pause', () => appendLog('Remote audio playback paused'));
  elements.remoteAudio.addEventListener('stalled', () => appendLog('Remote audio playback stalled'));
  elements.remoteAudio.addEventListener('waiting', () => appendLog('Remote audio playback waiting'));

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

  function setRemoteAudioStream(stream) {
    elements.remoteAudio.srcObject = stream;
    elements.remoteAudio.muted = false;
    elements.remoteAudio.volume = 1;
    if (typeof elements.remoteAudio.load === 'function') elements.remoteAudio.load();
  }

  function playRemoteAudio(context) {
    if (!elements.remoteAudio.srcObject) return;
    elements.remoteAudio.muted = false;
    elements.remoteAudio.volume = 1;
    const playPromise = elements.remoteAudio.play();
    if (playPromise && typeof playPromise.catch === 'function') {
      playPromise.catch((error) => {
        appendLog('Remote audio is ready; press Play in the audio controls');
        appendLog(`Remote audio playback failed (${context}): ${error?.name || 'Error'} ${error?.message || 'unknown error'}`);
      });
    }
  }

  function stopRtcStats() {
    if (rtcStatsTimer) {
      window.clearInterval(rtcStatsTimer);
      rtcStatsTimer = null;
    }
    previousRtcStats = null;
    previousRtcPath = null;
    rtcStatsSequence = 0;
    rtcStatsCallId = 'unknown';
  }

  function numberValue(value) {
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
  }

  function delta(current, previous, field) {
    if (!previous) return null;
    return numberValue(current[field]) - numberValue(previous[field]);
  }

  function audioStatsSummary(stats, direction) {
    const reports = [...stats.values()].filter((report) => (
      report.type === `${direction}-rtp`
      && (report.kind === 'audio' || report.mediaType === 'audio')
      && report.isRemote !== true
    ));
    const summary = {
      packets: 0,
      bytes: 0,
      packetsLost: 0,
      jitter: 0,
      audioLevel: null,
      totalAudioEnergy: 0,
      totalSamplesDuration: 0,
      concealedSamples: 0,
      silentConcealedSamples: 0,
      codecs: []
    };

    reports.forEach((report) => {
      summary.packets += numberValue(direction === 'inbound' ? report.packetsReceived : report.packetsSent);
      summary.bytes += numberValue(direction === 'inbound' ? report.bytesReceived : report.bytesSent);
      summary.packetsLost += numberValue(report.packetsLost);
      summary.jitter = Math.max(summary.jitter, numberValue(report.jitter));
      if (typeof report.audioLevel === 'number') summary.audioLevel = Math.max(summary.audioLevel ?? 0, report.audioLevel);
      summary.totalAudioEnergy += numberValue(report.totalAudioEnergy);
      summary.totalSamplesDuration += numberValue(report.totalSamplesDuration);
      summary.concealedSamples += numberValue(report.concealedSamples);
      summary.silentConcealedSamples += numberValue(report.silentConcealedSamples);
      const codec = stats.get(report.codecId);
      if (codec?.mimeType && !summary.codecs.includes(codec.mimeType)) summary.codecs.push(codec.mimeType);
    });

    return summary;
  }

  function formatAudioStats(label, current, previous) {
    const packetDelta = delta(current, previous, 'packets');
    const byteDelta = delta(current, previous, 'bytes');
    const energyDelta = delta(current, previous, 'totalAudioEnergy');
    const durationDelta = delta(current, previous, 'totalSamplesDuration');
    const concealedDelta = delta(current, previous, 'concealedSamples');
    const silentConcealedDelta = delta(current, previous, 'silentConcealedSamples');
    const details = [
      `${label}: pkts=${current.packets}${packetDelta === null ? '' : ` (+${packetDelta})`}`,
      `bytes=${current.bytes}${byteDelta === null ? '' : ` (+${byteDelta})`}`,
      `lost=${current.packetsLost}`,
      `jitter=${Math.round(current.jitter * 1000)}ms`
    ];

    if (current.audioLevel !== null) details.push(`level=${current.audioLevel.toFixed(4)}`);
    if (energyDelta !== null) details.push(`energy+${energyDelta.toFixed(4)}`);
    if (durationDelta !== null) details.push(`duration+${durationDelta.toFixed(2)}s`);
    if (concealedDelta !== null) details.push(`concealed+${concealedDelta}`);
    if (silentConcealedDelta !== null) details.push(`silent+${silentConcealedDelta}`);
    if (current.codecs.length > 0) details.push(`codec=${current.codecs.join(',')}`);

    return details.join(' ');
  }

  function selectedRtcPath(stats) {
    const pairs = [...stats.values()].filter((report) => (
      report.type === 'candidate-pair'
      && (report.selected || (report.nominated && report.state === 'succeeded'))
    ));
    if (pairs.length === 0) return null;
    const pair = pairs[0];
    const local = stats.get(pair.localCandidateId);
    const remote = stats.get(pair.remoteCandidateId);
    const formatCandidate = (candidate) => {
      if (!candidate) return 'unknown';
      const address = candidate.address || candidate.ip || candidate.ipAddress || 'unknown';
      const port = candidate.port || candidate.portNumber || 'unknown';
      return `${candidate.candidateType || 'candidate'}/${candidate.protocol || 'udp'} ${address}:${port}`;
    };
    return `${formatCandidate(local)} -> ${formatCandidate(remote)}`;
  }

  function compactNumber(value, digits = 4) {
    if (typeof value !== 'number' || !Number.isFinite(value)) return '';
    return Number(value.toFixed(digits)).toString();
  }

  function sessionCallId(session) {
    return session?.id
      || session?._request?.call_id
      || session?._dialog?.id?.call_id
      || 'unknown';
  }

  function sendRtcStatsBeacon(current, previous, path) {
    const params = new URLSearchParams({
      seq: String(++rtcStatsSequence),
      call: rtcStatsCallId,
      inPkts: String(current.inbound.packets),
      inDelta: String(delta(current.inbound, previous?.inbound, 'packets') ?? ''),
      inBytes: String(current.inbound.bytes),
      inLost: String(current.inbound.packetsLost),
      inJitterMs: String(Math.round(current.inbound.jitter * 1000)),
      inLevel: compactNumber(current.inbound.audioLevel),
      inEnergyDelta: compactNumber(delta(current.inbound, previous?.inbound, 'totalAudioEnergy')),
      inDurationDelta: compactNumber(delta(current.inbound, previous?.inbound, 'totalSamplesDuration'), 2),
      inConcealedDelta: String(delta(current.inbound, previous?.inbound, 'concealedSamples') ?? ''),
      inSilentDelta: String(delta(current.inbound, previous?.inbound, 'silentConcealedSamples') ?? ''),
      outPkts: String(current.outbound.packets),
      outDelta: String(delta(current.outbound, previous?.outbound, 'packets') ?? ''),
      outBytes: String(current.outbound.bytes),
      outLevel: compactNumber(current.outbound.audioLevel),
      path: path || ''
    });
    const beacon = new Image();
    beacon.src = `/rtc-stats.gif?${params.toString()}`;
  }

  function startRtcStats(peerconnection, session) {
    stopRtcStats();
    rtcStatsCallId = sessionCallId(session);

    const collectStats = async () => {
      if (!activeSession || peerconnection.signalingState === 'closed') {
        stopRtcStats();
        return;
      }

      try {
        const stats = await peerconnection.getStats();
        const current = {
          inbound: audioStatsSummary(stats, 'inbound'),
          outbound: audioStatsSummary(stats, 'outbound')
        };
        appendLog(formatAudioStats('RTC inbound audio', current.inbound, previousRtcStats?.inbound));
        appendLog(formatAudioStats('RTC outbound audio', current.outbound, previousRtcStats?.outbound));

        const path = selectedRtcPath(stats);
        if (path && path !== previousRtcPath) {
          appendLog(`RTC selected path: ${path}`);
          previousRtcPath = path;
        }
        sendRtcStatsBeacon(current, previousRtcStats, path);
        previousRtcStats = current;
      } catch (error) {
        appendLog(`RTC stats failed: ${error?.message || 'unknown error'}`);
      }
    };

    collectStats();
    rtcStatsTimer = window.setInterval(collectStats, 5000);
  }

  function patchRemoteAnswerMsid(sdp) {
    if (!sdp || sdp.includes('\na=msid:') || sdp.includes('\r\na=msid:')) return sdp;
    if (!/^m=audio /m.test(sdp)) return sdp;

    const eol = sdp.includes('\r\n') ? '\r\n' : '\n';
    const streamId = 'rtpengine-stream';
    const trackId = 'rtpengine-audio';
    let patched = sdp;

    if (!/^a=msid-semantic:/m.test(patched)) {
      patched = patched.replace(/^(m=audio )/m, `a=msid-semantic: WMS ${streamId}${eol}$1`);
    }

    patched = patched.replace(/^(m=audio [^\r\n]+)(\r?\n)/m, `$1$2a=msid:${streamId} ${trackId}$2`);

    const ssrcMatches = [...patched.matchAll(/^a=ssrc:(\d+)\s+/gm)];
    if (ssrcMatches.length > 0) {
      ssrcMatches.forEach((match) => {
        const ssrc = match[1];
        const ssrcMsidRegex = new RegExp(`^a=ssrc:${ssrc} msid:`, 'm');
        if (!ssrcMsidRegex.test(patched)) {
          const lastSsrcRegex = new RegExp(`^(a=ssrc:${ssrc} [^\r\n]+)(\\r?\\n)`, 'm');
          patched = patched.replace(lastSsrcRegex, `$1$2a=ssrc:${ssrc} msid:${streamId} ${trackId}$2`);
        }
      });
    }

    return patched;
  }

  function installRemoteAnswerSdpPatch(peerconnection) {
    if (peerconnection.__remoteAnswerSdpPatchInstalled) return;
    peerconnection.__remoteAnswerSdpPatchInstalled = true;
    const setRemoteDescription = peerconnection.setRemoteDescription.bind(peerconnection);
    peerconnection.setRemoteDescription = (description) => {
      if (description?.type !== 'answer') return setRemoteDescription(description);

      const lines = description.sdp.split(/\r?\n/);
      const interestLines = lines.filter(line => line.startsWith('m=') || line.startsWith('a=ssrc:') || line.startsWith('a=msid'));
      appendLog('Original Remote SDP key lines: ' + JSON.stringify(interestLines));

      const patchedSdp = patchRemoteAnswerMsid(description.sdp);
      const patchedLines = patchedSdp.split(/\r?\n/);
      const patchedInterest = patchedLines.filter(line => line.startsWith('m=') || line.startsWith('a=ssrc:') || line.startsWith('a=msid'));
      appendLog('Patched Remote SDP key lines: ' + JSON.stringify(patchedInterest));

      if (patchedSdp === description.sdp) return setRemoteDescription(description);

      appendLog('Patched remote SDP answer with media stream ID');
      return setRemoteDescription(new RTCSessionDescription({
        type: description.type,
        sdp: patchedSdp
      }));
    };
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
      stopRtcStats();
      releaseLocalMedia();
      setStatus(elements.callStatus, 'Idle');
      elements.remoteAudio.srcObject = null;
    }
  }

  function attachSession(session, incoming) {
    setSession(session, incoming);
    setStatus(elements.callStatus, incoming ? 'Incoming' : 'Calling', 'pending');
    appendLog(incoming ? `Incoming call from ${session.remote_identity.uri}` : 'Outgoing call started');

    const setupPeerConnection = (peerconnection) => {
      if (peerconnection.__setupDone) return;
      peerconnection.__setupDone = true;

      installRemoteAnswerSdpPatch(peerconnection);
      startRtcStats(peerconnection, session);
      peerconnection.addEventListener('track', (event) => {
        const stream = event.streams[0] || new MediaStream([event.track]);
        setRemoteAudioStream(stream);
        appendLog(`Remote ${event.track.kind} track received`);
        appendLog(`Remote ${event.track.kind} track state: muted=${event.track.muted} readyState=${event.track.readyState}`);
        event.track.addEventListener('unmute', () => appendLog('Remote audio packets received'), { once: true });
        event.track.addEventListener('unmute', () => playRemoteAudio('track-unmute'), { once: true });
        event.track.addEventListener('ended', () => appendLog('Remote audio track ended'), { once: true });
        playRemoteAudio('track');
      });
    };

    if (session.connection) {
      setupPeerConnection(session.connection);
    }

    session.on('peerconnection', ({ peerconnection }) => {
      setupPeerConnection(peerconnection);
    });
    session.on('trackAdded', () => playRemoteAudio('track-added'));
    session.on('progress', () => setStatus(elements.callStatus, 'Ringing', 'pending'));
    session.on('accepted', () => setStatus(elements.callStatus, 'Connecting', 'pending'));
    session.on('confirmed', () => {
      setStatus(elements.callStatus, 'Connected', 'online');
      elements.answer.disabled = true;
      elements.reject.disabled = true;
      appendLog('Call connected');
      playRemoteAudio('confirmed');
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

  function resolveWebSocketUri() {
    if (!config.wsTicketAuthEnabled) return config.webSocketUri;

    if (!webSocketTicket && typeof window.getWebSocketTicket === 'function') {
      window.setWebSocketTicket(window.getWebSocketTicket());
    }
    if (!webSocketTicket) {
      window.setWebSocketTicket(window.prompt('WebSocket ticket') || '');
    }
    if (!webSocketTicket) {
      throw new Error('WebSocket ticket is required');
    }

    const uri = new URL(config.webSocketUri);
    uri.searchParams.set(config.wsTicketQueryParam || 'ticket', webSocketTicket);
    return uri.toString();
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

    let webSocketUri;
    try {
      webSocketUri = resolveWebSocketUri();
    } catch (error) {
      setStatus(elements.registrationStatus, 'Failed', 'error');
      appendLog(error?.message || 'WebSocket ticket is required');
      return;
    }

    const socket = new JsSIP.WebSocketInterface(webSocketUri);
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

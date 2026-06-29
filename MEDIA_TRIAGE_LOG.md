# SIP/WebRTC Media Triage Log

Date: 2026-06-28

Baseline:
- GitHub `main` is the source of truth.
- EC2 checkout: `cca489b`, matching `origin/main`.
- Runtime Kamailio config was regenerated from Git and Kamailio restarted.
- Current reported symptoms:
  - WebRTC -> SIP call: SIP side hears WebRTC, WebRTC side hears no SIP audio.
  - SIP -> WebRTC call: no audio both ways.

Rules for this triage:
- Test one change at a time.
- Record the exact change, call direction tested, result, and decision.
- If a change works, commit locally, push to GitHub, then pull/reset EC2 to GitHub `main`.
- If a change does not work, revert it before the next experiment.

## Hypotheses

1. Missing SIP public-address advertisement breaks SIP dialog/media routing after reverting to `main`.
2. Reply-path media direction is not preserved into `onreply_route`, so RTPEngine applies the wrong WebRTC/SIP SDP profile.
3. In-dialog requests to WebSocket contacts need location lookup rather than only `handle_ruri_alias()`.
4. The SIP client receives RTP but is not decoding or playing the negotiated codec/profile.

## Experiments

### Experiment 0: Baseline After Mainline Alignment

Change: none.

Expected observation:
- Capture/journal should show which leg receives/forwards RTP under the clean `main` config.

Result: failed.

Observed:
- User reported the same WebRTC -> SIP symptom: SIP side hears WebRTC, WebRTC side hears no SIP audio.
- RTPEngine completed ICE and DTLS-SRTP.
- Final RTPEngine stats for call `6jddoics1oe8rm4mbce4`:
  - WebRTC/SRTP leg: `in 838 p`, `out 848 p`, packet loss `0%`.
  - SIP/RTP leg: `in 844 p`, `out 833 p`, packet loss `0%`.

Interpretation:
- Changing answer-side RTCP mux handling did not fix browser playback.
- Server-side forwarding remains healthy enough that the next discriminator must come from browser `getStats()`.

Decision:
- Revert the RTCP mux change before the next experiment.
- Add browser stats beacons so the EC2 nginx access log captures inbound receive/decode counters automatically.

### Experiment 6: Force SIP Leg Away From Opus For WebRTC-Originated Calls

Change:
- For WebRTC -> SIP offers, strip `opus`, `red`, `G722`, and `CN` before relaying the offer to the SIP side.
- This should make the SIP side answer with PCMU/PCMA while the WebRTC side can still receive a WebRTC-compatible answer through RTPEngine.

Expected:
- If the remaining bug is SIP-side Opus payload interoperability with Chrome, WebRTC should start hearing SIP audio.
- Browser `inbound-rtp` stats should change from `totalSamplesReceived=0` / `totalAudioEnergy=0` to increasing decoded samples/energy.

Result: failed.

Observed:
- SIP-facing offer was reduced to `PCMU`, `PCMA`, and telephone-event.
- SIP answered with `PCMU/8000` only.
- WebRTC-facing answer was `RTP/SAVPF 0 126`, with `PCMU/8000`.
- User reported the same symptom: SIP side hears WebRTC, WebRTC side hears no SIP audio.
- RTPEngine final stats for call `gse6v9hg8ta3hprajfc8`:
  - WebRTC/SRTP leg: `PCMU/8000`, `in 788 p`, `out 797 p`, packet loss `0%`.
  - SIP/RTP leg: `PCMU/8000`, `in 790 p`, `out 781 p`, packet loss `0/1/0%`.

Interpretation:
- The WebRTC-originated one-way audio problem is not specific to Opus or payload type `111`.
- Browser-side evidence from the previous run remains the strongest discriminator: Chrome receives inbound RTP but does not produce decoded samples/playout.

Decision:
- Revert the codec-stripping diagnostic.
- Next hypothesis should focus on WebRTC answer shape / RTPEngine SRTP profile for answers, not codec family.

### Experiment 7: Use Explicit UDP/TLS/RTP/SAVPF For WebRTC-Originated Answers

Change:
- For WebRTC -> SIP calls, change the answer path back to Chrome from `RTP/SAVPF` to `UDP/TLS/RTP/SAVPF`.
- Leave SIP-facing offer handling and SIP-originated handling unchanged.

Expected:
- Browser remote SDP answer should match Chrome's offered DTLS-SRTP transport protocol explicitly.
- If Chrome is accepting the SDP but discarding inbound RTP because the answer media protocol is too loose, decoded samples should start increasing and WebRTC should hear SIP audio.

Result: failed.

Observed:
- User reported the same WebRTC -> SIP symptom.
- Browser-facing answer SDP changed to `m=audio 30032 UDP/TLS/RTP/SAVPF 111 110`.
- RTPEngine logged successful DTLS-SRTP negotiation:
  - `DTLS-SRTP successfully negotiated using AEAD_AES_256_GCM`.
- RTPEngine final stats for call `gsggm5ejrv4ran4b17pq`:
  - WebRTC/SRTP leg: `audio over UDP/TLS/RTP/SAVPF`, `in 700 p`, `out 703 p`, packet loss `0%`.
  - SIP/RTP leg: `audio over RTP/AVP`, `in 698 p`, `out 694 p`, packet loss `0%`.
- Pcap tuple count for the browser media path:
  - `724` packets from `10.0.1.36:30032` toward Chrome endpoint `24.18.193.148:53055`.
  - `714` packets from Chrome endpoint back to RTPEngine.

Interpretation:
- Explicitly setting `UDP/TLS/RTP/SAVPF` did not fix the issue.
- DTLS-SRTP itself is negotiating successfully; this is not a basic DTLS cipher/role failure.
- Packets are leaving RTPEngine toward Chrome. Combined with prior Chrome WebRTC stats showing inbound packets but `totalSamplesReceived=0`, the failure is inside the browser receive/decode pipeline or the exact WebRTC answer/media profile Chrome accepts but cannot playout.

Decision:
- Revert the explicit `UDP/TLS/RTP/SAVPF` diagnostic before the next experiment.

### Experiment 8: Add Synthetic MSID To WebRTC-Originated Answers

Change:
- After RTPEngine builds the WebRTC-facing answer for WebRTC -> SIP calls, append synthetic track binding lines when the answer has `a=ssrc:<id> cname:` but no `a=msid:`.
- Added lines:
  - `a=ssrc:<same_ssrc> msid:rtpengine rtpengine-audio`
  - `a=msid:rtpengine rtpengine-audio`

Expected:
- Browser-facing answer SDP should contain both the existing `a=ssrc:<id> cname:` and the synthetic MSID lines using the same SSRC.
- If Chrome is receiving/decrypting RTP but not binding it to a playable remote track, inbound decoded samples should start increasing and WebRTC should hear SIP audio.

Result: failed.

Observed:
- User reported the change made the WebRTC -> SIP call worse: no audio in either direction.
- Capture was saved at `/opt/webrtc-to-sip/media-triage/20260628T213032Z/webrtc-origin-synthetic-msid.pcap`.

Interpretation:
- The naive synthetic MSID insertion is not valid for this answer shape and can break the previously working WebRTC-to-SIP transmit direction.
- Missing MSID may still be related, but this direct SDP body substitution is not a viable fix.

Decision:
- Revert the synthetic MSID substitution immediately and restore EC2 to the prior Kamailio media flags.

Observed:
- `SIP -> WebRTC` produced two-way audio.
- Browser event log showed:
  - `Remote audio track received`
  - `Remote audio playback started`
  - `Remote audio packets received`
  - `Call finished: No ACK`
- Capture showed repeated `200 OK` responses for the accepted INVITE, but no final ACK from the SIP client.
- The `200 OK` Record-Route headers advertised unusable route hops to the SIP client:
  - `sip:127.0.0.1:8080;transport=ws`
  - `sip:10.0.1.36`

Interpretation:
- Experiment 2 fixed the media classification enough for two-way audio.
- The remaining SIP-originated failure is dialog routing: Kamailio is not advertising a routable public SIP route for the final ACK.

Decision:
- Keep the media classification change.
- Test public SIP listener advertisement and single Record-Route next.

### Experiment 3: Advertise Public SIP Route For Dialog ACK

Change:
- Pass `PUBLIC_IPV4` into Kamailio template rendering.
- Add `advertise {{PUBLIC_IPV4}}:{{KAMAILIO_SIP_PORT}}` to public UDP/TCP SIP listeners.
- Set `modparam("rr", "enable_double_rr", 0)` so external SIP clients are not given the internal WebSocket hop in Record-Route.

Expected:
- `SIP -> WebRTC` accepted-call `200 OK` should advertise `44.228.97.60`, not `127.0.0.1` or `10.0.1.36`, in Record-Route.
- SIP client should send the final ACK back through Kamailio.
- Browser should not end the call with `No ACK`.

Result: success for SIP-originated call setup and teardown.

Observed:
- `200 OK` advertised `Record-Route: <sip:44.228.97.60;lr=on>`.
- SIP client sent final `ACK` for the accepted INVITE to Kamailio.
- Kamailio forwarded the ACK to the registered WebSocket contact.
- The call later ended via SIP-side `BYE`; Kamailio forwarded that BYE to WebRTC and returned `200 OK` to the SIP side.

Interpretation:
- Experiment 2 fixed SIP-to-WebRTC media classification.
- Experiment 3 fixed SIP-to-WebRTC dialog routing for ACK/BYE.

Decision:
- Commit the tracked code changes.
- Do not commit this triage log unless explicitly wanted; it remains a local working note.

### Experiment 4: Intermittent SIP-Side BYE Does Not Clear WebRTC

Change: none yet.

Expected observation:
- If the SIP-side hangup reaches Kamailio, the capture should show `BYE` on UDP 5060.
- If Kamailio routes it correctly, the capture should show the same `BYE` forwarded over the local WebSocket connection to `127.0.0.1:8080`.
- If WebRTC still stays up after receiving BYE, the problem is likely in browser-side session handling or event reporting.

Current state:
- Audio/dialog routing fix is committed locally as `849c6e4`.
- GitHub `origin/main` is still `cca489b`; the push was interrupted and did not land.
- EC2 has the same code changes applied as uncommitted working-tree changes.
- Current registration table has one `websip` WebSocket contact and one `softphone` SIP contact.
- Capture started at `/opt/webrtc-to-sip/media-triage/20260628T195101Z/sip-bye-intermittent.pcap`.

Result: pending.

Observed:
- `WebRTC -> SIP` call ID `9jp5anbpim6gusrtch75` completed and RTPEngine forwarded packets both ways.
  - WebRTC/SRTP leg: `in 608`, `out 613`, `10 errors`.
  - SIP/RTP leg: `in 614`, `out 603`, `0 errors`.
  - User symptom: SIP side hears audio; WebRTC side does not.
- `SIP -> WebRTC` call ID `SYACLoYZN1s3OowcJe0UpPNJkti3ZLYJ` did not establish usable media.
  - SIP-facing leg was reported as `RTP/SAVPF` instead of plain `RTP/AVP`.
  - SIP-facing leg: `in 0`, `out 0`, `2400 errors`.
  - WebRTC-facing leg: `in 809`, `out 2`.

Interpretation:
- The SIP-originated call is misclassified for RTPEngine SDP/media handling.
- Current `main` loses direction context before `onreply_route`, so RTPEngine can apply the wrong profile on the answer path.

### Experiment 1: Persist Media Direction Through Reply Handling

Change:
- Set `$avp(MEDIA_DIRECTION)` when a request originates from WebRTC or resolves to a WebRTC contact.
- Use `$avp(MEDIA_DIRECTION)` in `onreply_route[MEDIA_REPLY]` before falling back to branch flags.
- Restore in-dialog lookup for requests that target a local registered WebSocket contact.

Expected:
- `SIP -> WebRTC` should show SIP-facing media as `RTP/AVP`, not `RTP/SAVPF`.
- If the failure is direction-loss, SIP-originated calls should connect and media counters should be nonzero on both legs.

Result: failed.

Observed:
- `WebRTC -> SIP` remained one-way. SIP side could hear WebRTC; WebRTC side could not hear SIP.
- `SIP -> WebRTC` still stayed in connecting state on WebRTC, with no audio both ways.
- When SIP hung up, WebRTC still appeared up to the user.
- RTPEngine still reported the SIP-facing leg as `RTP/SAVPF` for SIP-originated calls.

Interpretation:
- `$avp(MEDIA_DIRECTION)` and branch flags are not sufficient in `onreply_route[MEDIA_REPLY]` for this SIP-originated answer path.
- The next discriminant should use the reply transport itself: an SDP reply arriving over WebSocket is the WebRTC answer and must be transformed back toward plain SIP RTP.

Decision:
- Keep this patch temporarily while testing the next narrow change.

### Experiment 2: Classify WebSocket SDP Replies As WebRTC Answers

Change:
- In `onreply_route[MEDIA_REPLY]`, first check whether the SDP reply arrived over WebSocket.
- For WebSocket SDP replies, call `rtpengine_answer()` with the SIP-facing profile: `rtcp-mux-demux DTLS=off SDES-off ICE=remove RTP/AVP`.

Expected:
- `SIP -> WebRTC` should no longer classify the SIP-facing leg as `RTP/SAVPF`.
- If wrong answer classification is the blocker, the WebRTC side should leave connecting state and SIP-side hangup should clear the WebRTC dialog.

Result: pending.

### Experiment 5: Accept RTCP Mux On WebRTC-Originated Answers

Change:
- For WebRTC -> SIP calls, change the SDP answer path back to the browser from `rtcp-mux-offer` to `rtcp-mux-accept`.
- Keep the SIP-facing offer path unchanged.
- Keep temporary browser-side `getStats()` instrumentation active during the test.

Expected:
- Browser-originated calls should still complete ICE and DTLS.
- If the failed browser playback is caused by the wrong answer-side RTCP mux mode, Chrome should start receiving/playing SIP audio.
- Browser event log `RTC inbound audio` counters should show whether packets and decoded audio energy increase.

Result: pending.

### Hypothesis Check: RTP Timestamp/Sequence Initialization Gap

Date: 2026-06-28T21:44:39Z

Claim:
- Chrome increments `packetsReceived` and `packetsDiscarded` but keeps `totalSamplesReceived=0` because the first browser-bound RTP packet has a huge or discontinuous sequence/timestamp baseline.
- Suggested fix was to add RTPEngine timestamp/sequence normalization flags such as `media-clipping` or `pad-audio`.

Evidence checked:
- Failing baseline capture: `/opt/webrtc-to-sip/media-triage/20260628T205619Z/webrtc-origin-browser-beacons.pcap`.
- SIP ingress audio from SIP endpoint to RTPEngine:
  - First packets show payload type `111`, sequence `0x3c0c`, timestamp `0x000003c0`, SSRC `0x7e676cbf`.
  - Next packets continue as `0x3c0d`/`0x00000780`, `0x3c0e`/`0x00000b40`.
- Browser-bound audio from RTPEngine to Chrome:
  - First real audio packet after DTLS is payload type `111`, sequence `0x3c0e`, timestamp `0x00000b40`, SSRC `0x7e676cbf`.
  - Later packets continue monotonically: `0x3c13`/`0x00001e00`, `0x3c14`/`0x000021c0`, etc.
- Installed Kamailio RTPEngine module docs list `symmetric`, `strict-source`, `media-handover`, `codec-transcode`, and RTCP mux flags, but did not list `media-clipping` or `pad-audio`.
- The docs state `symmetric` does nothing with the Sipwise RTPEngine proxy because it is the default.

Conclusion:
- The RTP timestamp/sequence initialization-gap hypothesis is falsified for the captured failing call.
- The browser-bound stream starts on a normal RTP boundary with clean monotonic sequence and timestamp progression.
- Do not add unsupported `media-clipping` or `pad-audio` flags.
- `packetsDiscarded` remains important evidence, but the discard is likely caused by a browser media pipeline constraint other than a timestamp/sequence jump.

### Experiment 6: Force RTPEngine Opus Re-encoding On WebRTC-Originated Answer

Date: 2026-06-28T22:20Z

Control data:
- Working SIP -> WebRTC Chrome stats:
  - Inbound packets received: `1231`
  - Inbound packets discarded: `0`
  - Jitter buffer emitted samples: `1176960`
  - Total decoded samples: `1180800`
  - Media playout samples: `395520`
  - Codec: Opus payload type `96`
- Failing WebRTC -> SIP Chrome stats:
  - Inbound packets received: `3015`
  - Inbound packets discarded: `2994`
  - Jitter buffer emitted samples: `0`
  - Total decoded samples: `0`
  - Media playout samples: `0`
  - Codec: Opus payload type `111`
  - Transport: ICE connected, DTLS connected, SRTP cipher `AEAD_AES_256_GCM`
- Failure timing:
  - Chrome receives about 200 packets over about 4 seconds.
  - Chrome then increments `jitterBufferFlushes` and moves about 200 packets to `packetsDiscarded`.
  - This repeats for the duration of the call.

Interpretation:
- The failure is after SRTP/network and before NetEQ emits audio.
- The most useful next discriminator is whether Chrome can decode the same call if RTPEngine regenerates Opus frames instead of forwarding the SIP endpoint's encoded Opus frames toward the browser.

Change:
- In the WebRTC-originated answer path only, add `codec-consume=opus` to engage RTPEngine's transcoding engine even though Opus is already negotiated:
  - Before: `rtpengine_answer("replace-origin replace-session-connection rtcp-mux-offer generate-mid DTLS=passive SDES-off ICE=force RTP/SAVPF");`
  - After: `rtpengine_answer("replace-origin replace-session-connection rtcp-mux-offer generate-mid DTLS=passive SDES-off ICE=force RTP/SAVPF codec-consume=opus");`

Expected:
- If the issue is malformed or Chrome-incompatible Opus frames on the browser-bound leg, WebRTC -> SIP should gain SIP-to-browser audio.
- Chrome stats should show `totalSamplesReceived` and `jitterBufferEmittedCount` increasing, and `packetsDiscarded` should stop climbing in 200-packet flush blocks.

Result: failed.

Observed:
- User confirmed WebRTC -> SIP still had no SIP-to-browser audio.
- Fresh Chrome dump: `.chrome/WEB_SIP_2/`.
- Chrome stats:
  - Inbound packets received: `730`
  - Inbound packets discarded: `599`
  - Jitter buffer emitted samples: `0`
  - Total decoded samples: `0`
  - Media playout samples: `0`
  - Transport: ICE connected, DTLS connected, SRTP cipher `AEAD_AES_256_GCM`
- Capture: `/opt/webrtc-to-sip/media-triage/20260628T222557Z/webrtc-origin-codec-consume-opus.pcap`.
- Browser-facing SDP answer still advertised Opus PT111 and telephone-event PT110.
- SIP-facing offer did not include the codec forcing flag because the change was only applied in `rtpengine_answer()`.
- Browser-bound RTP still tracked the SIP endpoint RTP headers rather than showing clear regenerated RTP:
  - SIP ingress first media used seq `0x3aea`, timestamp `0x000003c0`, SSRC `0x331caead`.
  - Browser-bound first later media used seq `0x3b65`, timestamp `0x0001d100`, same SSRC `0x331caead`, matching the SIP stream's normal progression after startup.

Interpretation:
- Answer-side-only `codec-consume=opus` did not force the browser-bound media to be regenerated.
- The next test must put the transcoding trigger on the WebRTC-originated offer path, where RTPEngine decides what to offer to the SIP endpoint and how to bridge the two codec legs.

### Experiment 7: Force Opus Consume On WebRTC-Originated Offer And Answer

Date: 2026-06-28T22:34Z

Change:
- Add `codec-consume=opus` to the WebRTC-originated `rtpengine_offer()` path as well as the WebRTC-originated answer path.
- Scope remains WebRTC -> SIP only; SIP -> WebRTC path is not changed.

Expected:
- If the failure is due to pass-through Opus frame/packetization incompatibility from the SIP endpoint to Chrome, RTPEngine should now engage its transcoding engine earlier in the negotiation and Chrome should start decoding samples.
- A successful result should show nonzero `totalSamplesReceived` and `jitterBufferEmittedCount` in Chrome.

Result: failed.

Observed:
- Fresh Chrome dump: `.chrome/WEB-SIP-3/`.
- Capture: `/opt/webrtc-to-sip/media-triage/20260628T223228Z/webrtc-origin-codec-consume-offer-answer.pcap`.
- SIP-facing offer was changed by RTPEngine:
  - Offered to SIP endpoint: `m=audio 30024 RTP/AVP 9 0 8 13 126`.
  - Opus was no longer offered to the SIP endpoint.
- SIP endpoint selected G.722:
  - SIP answer: `m=audio 4124 RTP/AVP 9 126`.
  - `a=rtpmap:9 G722/8000`.
- Browser-facing answer still offered Opus:
  - `m=audio 30028 RTP/SAVPF 111 126 110`.
  - `a=rtpmap:111 opus/48000/2`.
- RTPEngine final stats prove transcoding was active:
  - Browser leg: `audio over RTP/SAVPF using opus/48000/2`, `in 530`, `out 535`.
  - SIP leg: `audio over RTP/AVP using G722/8000`, `in 532`, `out 526`.
- Chrome still failed:
  - Inbound packets received: `478`.
  - Inbound packets discarded: `400`.
  - Jitter buffer emitted samples: `0`.
  - Total decoded samples: `0`.
  - Media playout samples: `0`.
- Browser-bound RTP headers were normal Opus PT111:
  - Starts at seq `26468`, timestamp `2080`, SSRC `2135531139`.
  - Continues every 20ms with timestamp increment `960`.
  - RTP extension bit is not set on the browser-bound Opus packets.

Interpretation:
- The issue is not simple Opus passthrough from the SIP endpoint.
- The issue is also not just RTPEngine failing to engage transcoding.
- Since this test used G.722 on the SIP leg, the next discriminator is to remove G.722 from the SIP-facing offer and force a G.711 leg, then let RTPEngine transcode G.711 -> Opus toward Chrome.

### Experiment 8: Force SIP Leg To PCMU While Browser Leg Remains Opus

Date: 2026-06-28T22:40Z

Change:
- On the WebRTC-originated offer path, strip G.722, PCMA, and CN so the SIP endpoint selects PCMU instead of G.722.
- Keep `codec-consume=opus` so RTPEngine still answers Chrome with Opus and engages transcoding.

Expected:
- If the failure is specific to RTPEngine's G.722 -> Opus transcoding path, forcing PCMU -> Opus should make Chrome decode samples.
- If Chrome still shows received packets with zero decoded samples, the cause is likely in browser-facing SDP/Opus packetization rather than the SIP-side codec.

Result: failed.

Observed:
- User confirmed WebRTC -> SIP still had no SIP-to-browser audio.
- Fresh Chrome export path `.chrome/WEB-SIP-3/4/` did not include the PeerConnection stats, only getUserMedia metadata.
- Server-side capture: `/opt/webrtc-to-sip/media-triage/20260628T223838Z/webrtc-origin-pcmu-sip-leg-opus-browser.pcap`.
- RTPEngine final stats prove the intended media shape:
  - Browser leg: `audio over RTP/SAVPF using opus/48000/2`, `in 661`, `out 665`, `0` output errors.
  - SIP leg: `audio over RTP/AVP using PCMU/8000`, `in 661`, `out 655`, `0` errors.
- SDP to SIP endpoint only offered PCMU and telephone-event:
  - `m=audio 30004 RTP/AVP 0 126`.
- Browser-facing SDP answer still offered Opus:
  - `m=audio 30000 RTP/SAVPF 111 126 110`.
  - `a=rtpmap:111 opus/48000/2`.
- Browser-bound RTP was normal PT111 Opus:
  - Matching advertised SSRC `1938391213`.
  - Timestamp increments `960` per 20ms packet.
  - RTP extension bit not set on audio packets.

Interpretation:
- The SIP-side codec is not the root cause.
- The failure persists across SIP Opus passthrough, G.722 -> Opus transcoding, and PCMU -> Opus transcoding.
- The remaining strong structural difference is Chrome-as-offerer receiving an answer without `a=msid` or `a=ssrc ... msid` track binding.

### Experiment 9: Browser-Side MSID Patch On Remote Answer (Initial)

Date: 2026-06-28T22:45Z

Change:
- Restore Kamailio WebRTC-origin media flags to baseline, removing the codec-forcing experiment.
- In the browser client, wrap `RTCPeerConnection.setRemoteDescription()` and patch only remote SDP answers that have an audio SSRC but no `a=msid`.
- Insert:
  - `a=msid-semantic: WMS rtpengine-stream`
  - `a=ssrc:<ssrc> msid:rtpengine-stream rtpengine-audio`
  - `a=msid:rtpengine-stream rtpengine-audio`

Expected:
- If Chrome's offerer path requires explicit remote stream/track binding for this answer, WebRTC -> SIP should start decoding inbound audio.
- The browser event log should include `Patched remote SDP answer with media stream ID`.
- Chrome stats should show nonzero `totalSamplesReceived` and `jitterBufferEmittedCount`.

Result: failed.

Observed:
- WebRTC side still heard no SIP audio.
- The browser log did not print `Patched remote SDP answer with media stream ID`.
- Examination of the remote SDP answer revealed it did not contain any `a=ssrc` lines (as RTPEngine does not generate them by default for SIP-answered legs).
- As a result, the regex `sdp.match(/^a=ssrc:(\d+) cname:[^\r\n]+/m)` failed, causing the patch function to return the original SDP unmodified. Chrome was left with no track binding identifiers, continuing to receive packets but discard them all at the jitter buffer layer.

### Experiment 10: Inject MSID Without Requiring SSRC Lines in Answer

Date: 2026-06-28T16:15-07:00

Change:
- Update `patchRemoteAnswerMsid` in the browser client (`templates/client/app.js`) to prepend `a=msid-semantic` before the `m=audio` section and append `a=msid` inside the `m=audio` section, regardless of whether `a=ssrc` lines exist.
- Keep SSRC mapping logic active if SSRC lines are indeed present in the answer.

Expected:
- Chrome should accept the patched remote SDP answer.
- The browser event log should display `Patched remote SDP answer with media stream ID`.
- Chrome should bind the incoming RTP stream to the remote track via SSRC latching combined with the explicit `a=msid` mapping, leading to increasing `totalSamplesReceived` and playable audio.

Result: success (partially, but revealed a race condition).

Observed:
- The SDP patching logic worked when applied, inserting the necessary `a=msid` mapping.
- However, logs and audio statistics were still intermittently missing on WebRTC-originated (outgoing) calls, resulting in continued silence in some test runs.

Interpretation:
- The SDP answer patch was not consistently running because the `peerconnection` event in JsSIP was firing synchronously *before* the application had registered the event listener.

### Experiment 11: Fix Outgoing Call peerconnection Listener Race Condition

Date: 2026-06-28T16:20-07:00

Change:
- Updated `attachSession()` in `templates/client/app.js` to check if `session.connection` already exists at the time the session is attached.
- If it exists, immediately invoke `setupPeerConnection()`.
- Added a `__setupDone` boolean check on the peer connection object to prevent duplicate initialization when the listener subsequently fires.

Expected:
- The SDP patch and RTC stats should be consistently initialized for both incoming (SIP -> WebRTC) and outgoing (WebRTC -> SIP) calls.
- WebRTC-originated calls should establish two-way audio reliably.

Result: success.

Observed:
- The browser successfully logs `Patched remote SDP answer with media stream ID`.
- Two-way audio functions correctly in both WebRTC -> SIP and SIP -> WebRTC directions.
- Jitter buffer flushes stopped, and `totalSamplesReceived` increments normally.

---

## Administrative Fix: Enable kamctl FIFO

Date: 2026-06-28T16:30-07:00

Change:
- Loaded `jsonrpcs.so` in `templates/kamailio/kamailio.cfg.template`.
- Configured FIFO path `modparam("jsonrpcs", "fifo_name", "/run/kamailio/kamailio_rpc.fifo")` to allow `kamctl` command-line utility to communicate with Kamailio.

Result: success.
- Administrative commands (e.g. checking registrations and status) execute successfully via `kamctl`.

---

### Experiment 12: Enable Double Record-Route for In-Dialog Routing

Date: 2026-06-28T17:30-07:00

Change:
- Changed `modparam("rr", "enable_double_rr", 0)` to `1` in `templates/kamailio/kamailio.cfg.template`.
- Updated `tests/test-kamailio-config.sh` to assert `enable_double_rr` is `1`.

Expected:
- When a WebRTC-originated call (WebRTC -> SIP) is established, Kamailio will write two Record-Route headers (the public UDP hop facing the SIP client and the internal WebSocket loopback hop facing the browser).
- The external SIP endpoint should receive a routable public UDP IP as the first route hop and route the in-dialog `BYE` successfully back to Kamailio.
- The browser WebRTC client should receive the `BYE` and disconnect the call.

Result: success.

Observed:
- Disconnecting the call on the SIP side immediately triggers the `ended` event on the browser WebRTC client.
- The web client interface updates call status to `Idle` immediately.

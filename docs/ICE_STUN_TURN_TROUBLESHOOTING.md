# ICE, STUN, and TURN Troubleshooting

| Symptom | Likely area | Check or action |
|---|---|---|
| Registration fails | HTTPS/WSS/Kamailio auth | Browser console and Nginx/Kamailio journals |
| Signaling works, no audio | RTPEngine/SDP/RTP/ICE | WebRTC internals, RTPEngine journal, RTP capture |
| STUN fails at home | NAT or UDP policy | Try `ICE_MODE=none` diagnostically, then explicit TURN |
| Home works, corporate Wi-Fi fails | Corporate filtering | Consider TURN TCP/TLS only after explicit enablement |
| RTP arrives but does not return | Advertised IP or CIDR | Check RTPEngine interface and security group |
| Calls work only with widened SG | Source address changed | Restore `/32` and update it to the current address |

`ICE_MODE=none` removes external ICE servers but is diagnostic only. TURN requires
`ENABLE_TURN=true`, strong long-term credentials, coturn configuration, and the
separate small relay range. Registration failure is not a STUN/TURN problem.

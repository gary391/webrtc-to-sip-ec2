# WebSocket Ticket Authentication

This feature gates SIP-over-WebSocket at Nginx before Kamailio sees the
upgrade. It is disabled by default and uses a local demo validator for synthetic
single-use tickets. Production login, KAA-JWT, VG ticket minting, and shared
cache integration are prerequisites owned outside this repository.

## Repo-Owned Contract

1. An external bootstrap/VG flow gives the browser a short-lived `ws_ticket`.
2. The browser opens `wss://<DOMAIN>/ws?ticket=<ticket>`.
3. Nginx runs `auth_request /ws-auth` before proxying `/ws`.
4. `/ws-auth` calls the local sidecar URL from `WS_AUTH_SIDECAR_URL`.
5. A valid unused ticket returns `204` and Nginx proxies the WebSocket upgrade
   to Kamailio.
6. Missing, malformed, expired, reused, unknown, or wrong-scope tickets return
   `401` or `403` and are rejected before Kamailio.

Nginx passes only minimal metadata to the sidecar: ticket, `Origin`, `Host`,
`X-Real-IP`, and `X-Request-ID`. When ticket auth is enabled, the request args
are not proxied to Kamailio, so ticket values are not forwarded downstream.

## Configuration

```text
ENABLE_WS_TICKET_AUTH=false
WS_AUTH_SIDECAR_URL=http://127.0.0.1:9090/validate
WS_TICKET_QUERY_PARAM=ticket
```

`ENABLE_WS_TICKET_AUTH=false` preserves the existing no-ticket `/ws` behavior.
When enabled, `WS_AUTH_SIDECAR_URL` must be a loopback HTTP URL and
`WS_TICKET_QUERY_PARAM` must be a simple Nginx `$arg_...` compatible parameter
name.

## Demo Sidecar

The demo sidecar lives at `sidecar/ws_ticket_sidecar.py`.

Mint a synthetic 60-second ticket:

```bash
python3 sidecar/ws_ticket_sidecar.py mint
```

Run the validator:

```bash
python3 sidecar/ws_ticket_sidecar.py serve --host 127.0.0.1 --port 9090
```

The state file contains hashes of opaque tickets, expiry timestamps, scopes, and
consumption timestamps. Validation updates the state under a file lock so a
ticket succeeds only once. Logs include a short hash prefix and never print raw
ticket values.

## Browser Behavior

The browser client keeps a ticket only in memory. External bootstrap code may
call:

```javascript
window.setWebSocketTicket(ticket);
```

For the demo, if ticket auth is enabled and no in-memory ticket exists, the
client prompts for a synthetic ticket at registration time. It then builds the
JsSIP WebSocket URI with `?<WS_TICKET_QUERY_PARAM>=...`.

A page refresh creates a new WebSocket connection and a new browser-generated
`Sec-WebSocket-Key`. JavaScript cannot set `Sec-WebSocket-Key`, and browsers
generate it per connection, so it is not an authentication carrier. Refresh,
reconnect, tab duplication, and JsSIP transport reconnect require a new
`ws_ticket` from the upstream bootstrap/VG flow. A consumed ticket must not be
reused.

## Out Of Scope

- Existing login cookie/session handling.
- `JSESSIONID` and BigIP extraction.
- KAA-JWT minting and 30-minute access-token cache.
- VG single-use `ws_ticket` minting.
- Real shared-cache or downstream service integration.

Kamailio remains unchanged in v1: `ws_handle_handshake()` is still the
WebSocket accept point after Nginx permits the upgrade, and SIP digest
authentication remains enabled after the WebSocket is established.

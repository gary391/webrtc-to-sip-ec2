# Browser SIP Client

The demo client uses JsSIP 3.13.8, which is distributed under the MIT license.
The pinned npm integrity value, bundle checksum, build command, and license are
stored in `templates/client/vendor/`.

The application and all dependencies are served from the EC2 origin. No SIP
password is written into HTML, JavaScript, CloudFormation, or Git. The operator
enters the browser account password at registration time.

## Accounts

Native MariaDB configuration idempotently creates two local subscribers from
the instance-only `.env`:

```text
SIP_USER=websip
SIP_PEER_USER=softphone
```

Both passwords are generated independently and remain in the mode-0600 `.env`.
Configure the browser with `SIP_USER` and a desktop SIP client with
`SIP_PEER_USER`. Both use the configured `DOMAIN` as registrar/realm.

Retrieve the generated demo credentials from the EC2 host when configuring the
two clients:

```bash
grep -E '^SIP_(USER|PASSWORD|PEER_USER|PEER_PASSWORD)=' \
  /opt/webrtc-to-sip/source/.env
```

Desktop softphone settings for the validated EC2 instance:

```text
Display name: softphone
Username / authentication user: value of SIP_PEER_USER
Password: value of SIP_PEER_PASSWORD
Domain / registrar / server: 44.228.97.60
Port: 5060
Transport: UDP
Outbound proxy: none
```

## Browser flow

1. Open the HTTPS endpoint from an address allowed by `DemoClientCidr`.
2. Enter the `SIP_USER` password and select **Register**.
3. Confirm the event log reports secure WebSocket connection and registration.
4. Register the peer account in a SIP softphone over UDP 5060.
5. Call `softphone` from the browser, or call `websip` from the softphone.
6. Allow microphone access when prompted. If it was previously blocked, set
   microphone access to **Allow** in the browser's site settings and confirm the
   browser is enabled in the operating system's microphone privacy settings.
7. Accept the incoming call and validate audio in both directions.
8. Hang up and confirm both endpoints tear down the dialog.

The default browser media configuration uses the rendered STUN server. TURN is
not enabled by this client or by the infrastructure unless explicitly selected.

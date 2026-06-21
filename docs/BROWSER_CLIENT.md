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

## Browser flow

1. Open the HTTPS endpoint from an address allowed by `DemoClientCidr`.
2. Enter the `SIP_USER` password and select **Register**.
3. Confirm the event log reports secure WebSocket connection and registration.
4. Register the peer account in a SIP softphone over UDP 5060.
5. Call `softphone` from the browser, or call `websip` from the softphone.
6. Accept the incoming call and validate audio in both directions.
7. Hang up and confirm both endpoints tear down the dialog.

The default browser media configuration uses the rendered STUN server. TURN is
not enabled by this client or by the infrastructure unless explicitly selected.

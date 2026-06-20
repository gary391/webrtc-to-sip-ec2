# Remote Development with VS Code

1. Run the CloudFormation `SshCommand` from a local terminal first.
2. Add the output snippet to `~/.ssh/config`, updating the key path.
3. Install the VS Code Remote - SSH extension.
4. Connect to `webrtc-to-sip-ec2` and open `/opt/webrtc-to-sip/source`.
5. Use the remote terminal for Debian-only checks such as APT, systemd, `sngrep`,
   `tcpdump`, and runtime validation.

Do not use the remote editor as a separate source tree. Pull clean commits with
`git pull --ff-only`. Experimental EC2 changes must be reimplemented and committed
locally before they become part of a validation result.

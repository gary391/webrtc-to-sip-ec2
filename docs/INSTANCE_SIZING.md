# Instance Sizing

`t3.medium` with standard CPU credits is the default: 2 vCPU and 4 GiB memory
leave room for media, database, packet capture, logs, and Remote SSH.

- `t3.small`: infrastructure smoke tests only.
- `t3.medium`: normal 1-3 call demo.
- `t3.large`: temporary packet capture, transcoding, or pressure investigation.
- `t3.micro`/`t2.micro`: unsupported as defaults because memory pressure obscures failures.

The 40-port RTP range is deliberately small. Capacity should remain 1-3 audio
calls, assuming up to four allocated UDP ports per call for conservative planning.

# Appgate customization: Minecraft server

Runs a vanilla Minecraft Java server on an Appgate SDP appliance as a
sandboxed, resource-capped systemd unit under a dedicated `mcserver` user.

## Build (Linux or WSL with internet)

    ./build.sh --accept-eula            # latest release
    ./build.sh --accept-eula --version 1.21.10

Downloads server.jar (SHA-1 verified against Mojang's manifest) and the
matching Eclipse Temurin JRE (SHA-256 verified), and writes
`appgate-minecraft.zip` (~110 MB; Appgate limit is 200 MB total).

Edit `src/data/minecraft.conf` first for port, allowed source CIDRs, heap
and memory/CPU caps.

## Deploy

1. On the target appliance (customizations are off by default):
   `sudo cz-config set -j customization/enabled true`
2. Admin UI > System > Appliance Customizations > +Add, upload the zip.
3. Select the customization in that appliance's configuration and save.
4. Check the appliance status in the dashboard (the `status` script reports).

## Operate

    sudo systemctl status cz-minecraft
    sudo journalctl -u cz-minecraft -f
    sudo ls /var/lib/cz-minecraft         # world, logs, server.properties

`server.properties` is only seeded on first start; edit the copy in
`/var/lib/cz-minecraft` and restart the customization to apply.

## Connecting through Appgate

- Players reaching the appliance through an Appgate client tunnel need an
  entitlement allowing TCP 25565 to the appliance's IP.
- The Gateway NATs tunnel traffic, so the appliance sees the Gateway's IP as
  the source. That IP must be inside `MC_ALLOW_FROM`.
- Players also need to reach `sessionserver.mojang.com:443` from their PC for
  login. With a full tunnel and no internet entitlement, they connect and
  then drop with "lost connection: Disconnected" in the server log.
- Everyone shares the Gateway IP, so use `/ban <player>`, never `/ban-ip`.

## Troubleshooting

    ss -ltn 'sport = :25565'                    # server listening?
    iptables -L CZ-MINECRAFT -n -v              # rule present, counters moving?
    tcpdump -ni any tcp port 25565              # SYNs arriving? SYN-ACK or RST back?

- No packets: blocked upstream (entitlement / Gateway).
- SYNs with no reply: firewall chain missing; re-run `/opt/customization/start`.
- SYNs answered with RST: server not listening yet (still starting or failed);
  check `journalctl -u cz-minecraft`.

## Behaviour notes

- `/opt/customization/stop` also removes the firewall chain. To apply config
  changes just re-run `start`; it restarts the server and rebuilds the chain.

- Firewall: a `CZ-MINECRAFT` iptables chain is inserted into INPUT, allowing
  only `MC_ALLOW_FROM`. If the appliance reloads its firewall (config change),
  the jump can disappear; `status` then reports a warning, and re-applying the
  customization (or a reboot) restores it. IPv4 only.
- `stop` sends SIGTERM (the server saves the world) and removes the firewall
  chain. The world and user are kept.
- Appliance upgrades are not guaranteed to preserve `/var/lib/cz-minecraft`;
  back up the world before upgrading.
- Starting and stopping writes audit entries via `auditgen`.

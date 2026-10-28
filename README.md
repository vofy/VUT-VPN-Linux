# VUT VPN on Linux

> [!NOTE]
> Tested on Fedora Workstation 44 with GNOME 50.6.

There are two ways to set it up:

- **A. Script.** Does everything in one step and also works on KDE Plasma, Debian/Ubuntu and Arch.
- **B. Manual + GNOME GUI.** Steps 1–5 below.

## A. Script

```bash
git clone https://github.com/vofy/VUT-VPN-Linux.git
cd vut-vpn-linux
chmod +x vut-vpn-nmconnection.sh
./vut-vpn-nmconnection.sh
```

Run it as your normal user (it calls `sudo` itself). It installs the L2TP plugin, allows IKEv1, enables IPsec and the L2TP kernel modules, then asks for:

- **VUT ID**: your VUT login (without @vut.cz or @vutbr.cz)
- **VUT PIN**: [vut.cz/intra/vut-pin](https://www.vut.cz/intra/vut-pin)
- **Pre-shared key**: from the [VUT VPN wiki](https://doc.vut.cz/cs/WifiSiteTelefony/VPN)

It installs the connection to `/etc/NetworkManager/system-connections/VUT.nmconnection`, readable by root only and visible only to your user. Then go to [step 5](#5-connect).

### Supported distributions

The script detects the distribution from `/etc/os-release`, including derivatives through `ID_LIKE`.

| Distribution | Package manager | IPsec backend | Status |
|---|---|---|---|
| Fedora, RHEL, AlmaLinux, Rocky Linux | `dnf` | libreswan | ✅ Tested on Fedora Workstation 44; others untested, RHEL-based need [EPEL](https://docs.fedoraproject.org/en-US/epel/) |
| Debian, Ubuntu, Linux Mint, Pop!_OS | `apt` | libreswan | ⚠️ Untested |
| Arch Linux, Manjaro, EndeavourOS | `pacman` | strongswan | ⚠️ Untested |

Any other distribution stops with an error. Use the manual steps (B) there and adapt the package names.

## B. Manual + GNOME GUI

## 1. Install the L2TP plugin

```bash
sudo dnf install NetworkManager-l2tp NetworkManager-l2tp-gnome
```

## 2. Allow IKEv1

Edit `/etc/ipsec.conf` and add `ikev1-policy=accept` under `config setup`:

```
config setup
        ikev1-policy=accept
```

Then enable IPsec and restart it so the new setting is loaded:

```bash
sudo systemctl enable --now ipsec
sudo systemctl restart ipsec
systemctl is-enabled ipsec && systemctl is-active ipsec   # should print "enabled" and "active"
```

## 3. Enable the L2TP kernel modules

```bash
sudo modprobe -a l2tp_netlink l2tp_ppp
echo -e "l2tp_netlink\nl2tp_ppp" | sudo tee /etc/modules-load.d/l2tp.conf
sudo systemctl restart NetworkManager
```

## 4. Import VUT.conf

1. In `VUT.conf` from this repository, replace `<vut_id>` with your VUT login (without @vut.cz or @vutbr.cz).
2. Open **Settings → Network**, click **+** next to **VPN**, then choose **Import from file…** and select `VUT.conf`.
3. Click **Add**. Nothing else needs to be filled in.

## 5. Connect

Turn on the **VUT** VPN in **Settings → Network** or in the top-bar quick settings menu.

If you used the GUI setup (B), the first connect asks for:

| Field | Value |
|---|---|
| **Password** | your VUT PIN ([vut.cz/intra/vut-pin](https://www.vut.cz/intra/vut-pin)), not your intraportal password |
| **Pre-shared key** | the shared secret from the [VUT VPN wiki](https://doc.vut.cz/cs/WifiSiteTelefony/VPN) |

The script (A) already stores both, so it connects without asking.

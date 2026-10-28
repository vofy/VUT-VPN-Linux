# VUT VPN on Linux

> [!NOTE]
> Tested on Fedora Workstation 44 with GNOME 50.6.

There are two ways to set it up:

- **A. Script.** Does everything in one step and also works on KDE Plasma, Debian/Ubuntu and Arch.
- **B. Manual + GNOME GUI.** Steps 1–5 below.

## A. Script

```bash
git clone https://github.com/<user>/vut-vpn-linux.git
cd vut-vpn-linux
chmod +x vut-vpn-nmconnection.sh
./vut-vpn-nmconnection.sh
```

Run it as your normal user (it calls `sudo` itself). It installs the L2TP plugin, allows IKEv1, enables IPsec and the L2TP kernel modules, then asks for:

- **VUT ID**: your VUT login (without @vut.cz or @vutbr.cz)
- **VUT PIN**: [vut.cz/intra/vut-pin](https://www.vut.cz/intra/vut-pin)
- **Pre-shared key**: from the [VUT VPN wiki](https://doc.vut.cz/cs/WifiSiteTelefony/VPN)

It installs the connection to `/etc/NetworkManager/system-connections/VUT.nmconnection`, readable by root only and visible only to your user. Then go to [step 5](#5-connect).

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

1. Open **Settings → Network**, click **+** next to **VPN**, then choose **Import from file…** and select `VUT.conf` from this repository.
2. The connection dialog opens on the **Identity** tab. Fill in:

   | Field | Value |
   |---|---|
   | **User authentication → User name** | your VUT login |
   | **User authentication → Password** | your VUT PIN ([vut.cz/intra/vut-pin](https://www.vut.cz/intra/vut-pin)), not your intraportal password |
   | **Machine authentication → Pre-shared key** | the shared secret from the [VUT VPN wiki](https://doc.vut.cz/cs/WifiSiteTelefony/VPN) |

   - The icon at the right of the **Password** field controls how the PIN is stored. Choose **Store the password only for this user** to save it, or **Ask for this password every time**.
   - On older plugin versions, the pre-shared key field is under the **IPsec Settings…** button instead.
3. Optional: to keep the connection to your user only, untick **Make available to other users** on the **Details** tab.
4. Click **Add**.

## 5. Connect

Turn on the **VUT** VPN in **Settings → Network** or in the top-bar quick settings menu. If you chose **Ask for this password every time**, enter your VUT PIN when prompted.

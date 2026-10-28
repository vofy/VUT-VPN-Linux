# VUT VPN on Linux

> [!NOTE]
> Tested on Fedora Workstation 44 with GNOME 50.6. Other distributions are untested.

You will need:

- **VUT ID**: your VUT login (without @vut.cz or @vutbr.cz)
- **VUT PIN**: [vut.cz/intra/vut-pin](https://www.vut.cz/intra/vut-pin)
- **Pre-shared key**: from the [VUT VPN wiki](https://doc.vut.cz/cs/WifiSiteTelefony/VPN)

There are three ways to set it up:

1. [Script](#1-script): does everything, including the connection (nmcli).
2. [GNOME GUI](#2-gnome-gui): import a connection file in GNOME Settings.
3. [Manual](#3-manual): packages, IPsec, kernel modules and an nmcli command.

## 1. Script

```bash
curl -fsSL https://raw.githubusercontent.com/vofy/VUT-VPN-Linux/main/vut-vpn-setup.sh | bash
```

Use `bash`, not `sh`. The script installs the packages, configures IPsec and the kernel modules, then asks for your VUT ID, VUT PIN and pre-shared key and creates the connection with nmcli.

Then turn on **VUT** in network settings, or run `nmcli connection up VUT`.

To remove the connection (packages and system settings stay):

```bash
curl -fsSL https://raw.githubusercontent.com/vofy/VUT-VPN-Linux/main/vut-vpn-setup.sh | bash -s -- --remove
```

## 2. GNOME GUI

First do the [packages](#packages) (including the GNOME package), [IPsec](#ipsec-libreswan-5) and [kernel modules](#kernel-modules) steps from the manual setup.

Then download [`VUT.conf`](VUT.conf) with your VUT ID filled in:

```bash
read -rp "VUT ID: " VUT_ID && curl -fsSL https://raw.githubusercontent.com/vofy/VUT-VPN-Linux/main/VUT.conf | sed "s/^user=.*/user=$VUT_ID/" > VUT.conf
```

Go to **Settings → Network → VPN → + → Import from file…** and select `VUT.conf`. On the first connect, enter your VUT PIN and the pre-shared key.

## 3. Manual

### Packages

| Distribution | Command |
|---|---|
| Fedora, RHEL¹ | `sudo dnf install NetworkManager-l2tp kernel-modules-extra` |
| Debian, Ubuntu² | `sudo apt install network-manager-l2tp libreswan` |
| Arch | `sudo pacman -S networkmanager-l2tp strongswan` |

¹ RHEL, AlmaLinux and Rocky need [EPEL](https://docs.fedoraproject.org/en-US/epel/).
² On Ubuntu also install `linux-modules-extra-$(uname -r)`.

Optional GUI packages for editing the connection in network settings:

| Distribution | GNOME | KDE Plasma |
|---|---|---|
| Fedora, RHEL | `NetworkManager-l2tp-gnome` | `plasma-nm-l2tp` |
| Debian, Ubuntu | `network-manager-l2tp-gnome` | `plasma-nm` |
| Arch | included in `networkmanager-l2tp` | `plasma-nm` |

### IPsec (libreswan 5+)

Add `ikev1-policy=accept` under `config setup` in `/etc/ipsec.conf`, then:

```bash
sudo systemctl enable --now ipsec
sudo systemctl restart ipsec
```

### Kernel modules

```bash
sudo modprobe -a l2tp_netlink l2tp_ppp
printf 'l2tp_netlink\nl2tp_ppp\n' | sudo tee /etc/modules-load.d/l2tp.conf
sudo systemctl restart NetworkManager
```

### Connection

```bash
read -rp  "VUT ID: " VUT_ID
read -rsp "VUT PIN: " VUT_PIN; echo
read -rsp "Pre-shared key: " VUT_PSK; echo

nmcli connection add type vpn con-name VUT vpn-type l2tp \
  connection.autoconnect no \
  connection.permissions "user:$USER" \
  vpn.data "gateway=vpn.vutbr.cz, user=$VUT_ID, user-auth-type=password, password-flags=0, machine-auth-type=psk, ipsec-enabled=yes, ipsec-psk-flags=0, refuse-eap=yes, refuse-pap=yes, refuse-chap=yes, refuse-mschap=yes" \
  vpn.secrets "password=$VUT_PIN, ipsec-psk=$VUT_PSK"

unset VUT_PIN VUT_PSK
```

Values containing a comma don't work with nmcli. In that case, use the GNOME GUI method.

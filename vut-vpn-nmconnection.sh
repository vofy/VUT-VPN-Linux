#!/usr/bin/env bash
# Set up VUT VPN (L2TP/IPsec) for NetworkManager:
#   - installs the L2TP plugin (Fedora, Debian/Ubuntu, Arch)
#   - allows IKEv1 in libreswan, enables IPsec
#   - loads the L2TP kernel modules (now and on boot)
#   - generates and installs the VUT connection
# Tested on Fedora Workstation 44 with GNOME.
#
# Usage (as your normal user; sudo is called when installing):
#   ./vut-vpn-nmconnection.sh
#
# Asks for VUT ID, VUT PIN and pre-shared key, then installs
# /etc/NetworkManager/system-connections/VUT.nmconnection
#
# Pre-shared key: https://doc.vut.cz/cs/WifiSiteTelefony/VPN
# VUT PIN:        https://www.vut.cz/intra/vut-pin

set -euo pipefail

CON_NAME="VUT"
GATEWAY="vpn.vutbr.cz"
TARGET_DIR="/etc/NetworkManager/system-connections"

# Escape a value for a GKeyFile (backslash and leading/trailing spaces).
kf_escape() {
  local v="${1//\\/\\\\}"
  [[ "$v" == " "* ]] && v="\\s${v:1}"
  printf '%s' "$v"
}

gen_uuid() {
  if command -v uuidgen >/dev/null; then uuidgen
  else cat /proc/sys/kernel/random/uuid; fi
}

# --- System setup: packages, IPsec, kernel modules -----------------------------
# Only Fedora is tested; Debian/Ubuntu and Arch are best effort.
. /etc/os-release
DISTRO=" ${ID:-} ${ID_LIKE:-} "

echo "==> Installing required packages"
case "$DISTRO" in
  *" fedora "*|*" rhel "*)
    # libreswan is pulled in as a dependency of NetworkManager-l2tp
    sudo dnf install -y NetworkManager-l2tp NetworkManager-l2tp-gnome kernel-modules-extra
    ;;
  *" debian "*|*" ubuntu "*)
    sudo apt-get update
    sudo apt-get install -y network-manager-l2tp network-manager-l2tp-gnome libreswan
    # Ubuntu ships the L2TP modules in linux-modules-extra
    sudo apt-get install -y "linux-modules-extra-$(uname -r)" 2>/dev/null || true
    ;;
  *" arch "*)
    # Arch's networkmanager-l2tp uses strongswan (libreswan is only in the AUR)
    sudo pacman -S --needed --noconfirm networkmanager-l2tp strongswan
    ;;
  *)
    echo "Unsupported distribution '${ID:-unknown}'. Install the NetworkManager L2TP plugin manually." >&2
    exit 1
    ;;
esac

# Libreswan 5.x blocks IKEv1 by default; L2TP/IPsec needs it.
if command -v ipsec >/dev/null && ipsec --version 2>/dev/null | grep -qi libreswan; then
  LSW_MAJOR="$(ipsec --version | grep -oE '[0-9]+\.[0-9]+' | head -n1 | cut -d. -f1)"
  if [[ "${LSW_MAJOR:-0}" -ge 5 ]] && ! sudo grep -qE '^\s*ikev1-policy\s*=\s*accept' /etc/ipsec.conf; then
    echo "==> Allowing IKEv1 in /etc/ipsec.conf"
    sudo cp /etc/ipsec.conf "/etc/ipsec.conf.bak.$(date +%s)"
    sudo sed -i '/^\s*ikev1-policy\s*=/d; /^config setup/a\        ikev1-policy=accept' /etc/ipsec.conf
  fi
  echo "==> Enabling IPsec service"
  sudo systemctl enable --now ipsec
  sudo systemctl restart ipsec
fi

echo "==> Loading L2TP kernel modules"
sudo modprobe -a l2tp_netlink l2tp_ppp
printf 'l2tp_netlink\nl2tp_ppp\n' | sudo tee /etc/modules-load.d/l2tp.conf >/dev/null

sudo systemctl restart NetworkManager
sleep 2

# --- Questions ---------------------------------------------------------------
read -rp "VUT ID: " VUT_LOGIN
[[ -n "$VUT_LOGIN" ]] || { echo "VUT ID is required." >&2; exit 1; }

read -rsp "VUT PIN: " VUT_PIN; echo
[[ -n "$VUT_PIN" ]] || { echo "VUT PIN is required." >&2; exit 1; }

echo "Pre-shared key: see https://doc.vut.cz/cs/WifiSiteTelefony/VPN"
read -rsp "Pre-shared key: " VUT_PSK; echo
[[ -n "$VUT_PSK" ]] || { echo "Pre-shared key is required." >&2; exit 1; }

# Connection is visible only to the user running the script.
OWNER="${SUDO_USER:-$(id -un)}"

# --- Generate file -------------------------------------------------------------
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
chmod 600 "$TMP"

{
  echo "[connection]"
  echo "id=$CON_NAME"
  echo "uuid=$(gen_uuid)"
  echo "type=vpn"
  echo "autoconnect=false"
  echo "permissions=user:$OWNER;"
  echo
  echo "[vpn]"
  echo "service-type=org.freedesktop.NetworkManager.l2tp"
  echo "gateway=$GATEWAY"
  echo "user-auth-type=password"
  echo "user=$(kf_escape "$VUT_LOGIN")"
  echo "password-flags=0"
  echo "machine-auth-type=psk"
  echo "ipsec-enabled=true"
  echo "ipsec-psk-flags=0"
  echo "refuse-eap=true"
  echo "refuse-pap=true"
  echo "refuse-chap=true"
  echo "refuse-mschap=true"
  echo
  echo "[vpn-secrets]"
  echo "ipsec-psk=$(kf_escape "$VUT_PSK")"
  echo "password=$(kf_escape "$VUT_PIN")"
  echo
  echo "[ipv4]"
  echo "method=auto"
  echo
  echo "[ipv6]"
  echo "method=auto"
} > "$TMP"

# --- Install -------------------------------------------------------------------
if nmcli -t -f NAME connection show | grep -qx "$CON_NAME"; then
  read -rp "Connection '$CON_NAME' already exists. Replace it? [y/N]: " REPLACE
  [[ "$REPLACE" =~ ^[Yy] ]] || { echo "Aborted."; exit 1; }
  sudo nmcli connection delete "$CON_NAME" >/dev/null
fi

sudo install -m 600 -o root -g root "$TMP" "$TARGET_DIR/$CON_NAME.nmconnection"
sudo nmcli connection reload
echo "Installed $TARGET_DIR/$CON_NAME.nmconnection"
echo "Connect with: nmcli connection up $CON_NAME  (or from GNOME quick settings)"

#!/usr/bin/env bash
# Set up VUT VPN (L2TP/IPsec) for NetworkManager:
#   - installs the L2TP plugin (Fedora, Debian/Ubuntu, Arch)
#   - allows IKEv1 in libreswan
#   - loads the L2TP kernel modules (now and on boot)
#   - creates the VUT connection with nmcli
# Tested on Fedora Workstation 44 with GNOME.
#
# Usage (as your normal user; sudo is called when needed):
#   ./vut-vpn-setup.sh            # set up and install the connection
#   ./vut-vpn-setup.sh --remove   # remove the VUT connection
# or without cloning:
#   curl -fsSL https://raw.githubusercontent.com/vofy/VUT-VPN-Linux/main/vut-vpn-setup.sh | bash
#
# Asks for VUT ID, VUT PIN and pre-shared key, then creates the
# connection with `nmcli connection add`.
#
# Pre-shared key: https://doc.vut.cz/cs/WifiSiteTelefony/VPN
# VUT PIN:        https://www.vut.cz/intra/vut-pin

set -euo pipefail

# Wrapped in main() so a partially downloaded script (curl | bash) never runs.
main() {

CON_NAME="VUT"
GATEWAY="vpn.vutbr.cz"

case "${1:-}" in
  "") ;;
  -r|--remove)
    if nmcli -t -f NAME connection show | grep -qx "$CON_NAME"; then
      sudo nmcli connection delete "$CON_NAME"
    else
      echo "Connection '$CON_NAME' not found."
    fi
    echo "Removed. Installed packages, /etc/ipsec.conf and kernel module settings were left unchanged."
    exit 0
    ;;
  -h|--help)
    echo "Usage: vut-vpn-setup.sh [--remove]"
    echo "  (no option)  install packages, configure IPsec and create the VUT connection"
    echo "  --remove     remove the VUT connection"
    exit 0 ;;
  *) echo "Unknown option: $1 (use --help)" >&2; exit 1 ;;
esac

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
  # No need to enable/restart ipsec: the L2TP plugin restarts it on every connect.
fi

echo "==> Loading L2TP kernel modules"
sudo modprobe -a l2tp_netlink l2tp_ppp
printf 'l2tp_netlink\nl2tp_ppp\n' | sudo tee /etc/modules-load.d/l2tp.conf >/dev/null

sudo systemctl restart NetworkManager
sleep 2

# --- Questions ---------------------------------------------------------------
cat <<'EOF'

==> VUT VPN connection
    VUT ID          your VUT login (without @vut.cz or @vutbr.cz)
    VUT PIN         https://www.vut.cz/intra/vut-pin
    Pre-shared key  https://doc.vut.cz/cs/WifiSiteTelefony/VPN

EOF

read -rp "VUT ID: " VUT_LOGIN </dev/tty
[[ -n "$VUT_LOGIN" ]] || { echo "VUT ID is required." >&2; exit 1; }

read -rsp "VUT PIN: " VUT_PIN </dev/tty; echo
[[ -n "$VUT_PIN" ]] || { echo "VUT PIN is required." >&2; exit 1; }

read -rsp "Pre-shared key: " VUT_PSK </dev/tty; echo
[[ -n "$VUT_PSK" ]] || { echo "Pre-shared key is required." >&2; exit 1; }

# nmcli separates vpn.data/vpn.secrets items with ", "
for v in "$VUT_LOGIN" "$VUT_PIN" "$VUT_PSK"; do
  [[ "$v" != *,* ]] || { echo "Values must not contain a comma. Use the GNOME GUI method instead." >&2; exit 1; }
done

# Connection is visible only to the user running the script.
OWNER="${SUDO_USER:-$(id -un)}"

# --- Create connection ---------------------------------------------------------
if nmcli -t -f NAME connection show | grep -qx "$CON_NAME"; then
  read -rp "Connection '$CON_NAME' already exists. Replace it? [y/N]: " REPLACE </dev/tty
  [[ "$REPLACE" =~ ^[Yy] ]] || { echo "Aborted."; exit 1; }
  sudo nmcli connection delete "$CON_NAME" >/dev/null
fi

sudo nmcli connection add type vpn con-name "$CON_NAME" vpn-type l2tp \
  connection.autoconnect no \
  connection.permissions "user:$OWNER" \
  vpn.data "gateway=$GATEWAY, user=$VUT_LOGIN, user-auth-type=password, password-flags=0, machine-auth-type=psk, ipsec-enabled=yes, ipsec-psk-flags=0, refuse-eap=yes, refuse-pap=yes, refuse-chap=yes, refuse-mschap=yes" \
  vpn.secrets "password=$VUT_PIN, ipsec-psk=$VUT_PSK" >/dev/null

echo "Connection '$CON_NAME' created."
echo "Connect with: nmcli connection up $CON_NAME  (or from GNOME quick settings)"
}

main "$@"

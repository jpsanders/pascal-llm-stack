#!/bin/bash
# ============================================================================
# Installs the smoke test so a kernel update cannot break the stack quietly.
#
#   /usr/local/sbin/pascal-smoke-test     the test itself (smoke-test.sh)
#   /etc/kernel/postinst.d/zz-pascal-dkms-check
#   /etc/kernel/header_postinst.d/zz-pascal-dkms-check
#       run after DKMS's own hooks when a new kernel or its headers are
#       installed, and warn loudly, before you reboot, if the nvidia module
#       did not build for that kernel
#   pascal-smoke-test.service
#       runs the full test once on the first boot of each new kernel; a
#       failure shows in `systemctl --failed` and in
#       `journalctl -u pascal-smoke-test`
#
# Run with:  sudo bash 05-checks/install-smoke-test.sh
# Remove:    sudo bash 05-checks/install-smoke-test.sh --remove
# ============================================================================
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
DRIVER_VERSION="${DRIVER_VERSION:-570.211.01}"

if [ "${1:-}" = "--remove" ]; then
    systemctl disable --now pascal-smoke-test.service 2>/dev/null || true
    rm -f /etc/systemd/system/pascal-smoke-test.service \
          /etc/kernel/postinst.d/zz-pascal-dkms-check \
          /etc/kernel/header_postinst.d/zz-pascal-dkms-check \
          /usr/local/sbin/pascal-smoke-test
    systemctl daemon-reload
    echo "removed"
    exit 0
fi

install -m 0755 "$HERE/smoke-test.sh" /usr/local/sbin/pascal-smoke-test
mkdir -p /var/lib/pascal-smoke

# The kernel hook. Ubuntu builds DKMS modules when the image is installed
# and again when its headers are, so the check sits after both of DKMS's
# hooks; without headers yet it says so and waits for the headers' turn.
mkdir -p /etc/kernel/postinst.d /etc/kernel/header_postinst.d
cat > /etc/kernel/postinst.d/zz-pascal-dkms-check <<HOOK
#!/bin/sh
# Installed by pascal-llm-stack/05-checks/install-smoke-test.sh
kver="\$1"
[ -n "\$kver" ] || exit 0
if [ ! -e "/lib/modules/\$kver/build" ]; then
    echo "pascal-smoke: headers for \$kver are not installed yet; the nvidia build is checked when they are"
    exit 0
fi
if dkms status -m nvidia -v $DRIVER_VERSION -k "\$kver" 2>/dev/null | grep -q ": installed"; then
    echo "pascal-smoke: nvidia $DRIVER_VERSION built for \$kver"
else
    msg="nvidia $DRIVER_VERSION did NOT build for kernel \$kver. Do not reboot into it until it does: read /var/lib/dkms/nvidia/$DRIVER_VERSION/build/make.log, then sudo dkms autoinstall -k \$kver"
    echo "pascal-smoke: WARNING: \$msg" >&2
    logger -p user.err -t pascal-smoke "\$msg" 2>/dev/null || true
    echo "\$kver" > /var/lib/pascal-smoke/dkms-failed 2>/dev/null || true
fi
exit 0
HOOK
chmod 0755 /etc/kernel/postinst.d/zz-pascal-dkms-check
cp /etc/kernel/postinst.d/zz-pascal-dkms-check /etc/kernel/header_postinst.d/zz-pascal-dkms-check

cat > /etc/systemd/system/pascal-smoke-test.service <<UNIT
[Unit]
Description=Pascal stack smoke test, once per new kernel
After=network-online.target llama-server.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pascal-smoke-test --boot
Environment=DRIVER_VERSION=$DRIVER_VERSION

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable pascal-smoke-test.service

echo "installed. Running the test once now:"
/usr/local/sbin/pascal-smoke-test || true

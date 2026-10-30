#!/usr/bin/env bash
# Удаление связки mx-master-4-ubuntu. По умолчанию — только пользовательская часть.
# Полное удаление (включая venv, AppImage, root-файлы): bash uninstall.sh --full
set -euo pipefail
log() { echo -e "\033[1;32m[$(date +%T)]\033[0m $*"; }

systemctl --user disable --now mx4-ratchet.timer solaar.service mx4-resume.service 2>/dev/null || true
pkill -f "venvs/solaar/bin" 2>/dev/null || true
pkill -x kando 2>/dev/null || true

rm -f ~/.config/systemd/user/{solaar.service,mx4-ratchet.service,mx4-ratchet.timer,mx4-resume.service}
rm -f ~/.config/autostart/{solaar.desktop,kando.desktop}
rm -f ~/.local/bin/{solaar,solaar-start,kando,kando-show-menu,mx4-fix-ratchet,mx4-resume-fix}
systemctl --user daemon-reload
log "Пользовательская часть удалена (конфиги ~/.config/{solaar,kando} оставлены)."

if [ "${1:-}" = "--full" ]; then
    read -r -p "Полное удаление: venv, AppImage, конфиги и root-файлы (sudo)? [y/N] " ans
    [ "$ans" = "y" ] || exit 0
    sudo rm -f /etc/udev/rules.d/99-solaar-uinput.rules /usr/lib/systemd/system-sleep/mx4-resume.hook
    sudo deluser "$USER" input || true
    rm -rf ~/.local/venvs/solaar ~/lib/conda ~/Applications/Kando-3.0.1-x86_64.AppImage
    rm -rf ~/.config/solaar ~/.config/kando
    log "Удалено полностью (apt-пакет solaar не тронут: sudo apt remove solaar — при желании вручную)."
fi

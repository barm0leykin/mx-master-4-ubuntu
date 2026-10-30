#!/usr/bin/env bash
# =============================================================================
# Установка связки Logitech MX Master 4 на Ubuntu 22.04 (KDE, X11):
#   Solaar 1.1.20 (жесты, правила) + Kando (радиальное меню на haptic-кнопке)
#   + авто-фиксы (сброс трещотки, восстановление после suspend).
# Запуск: bash install.sh   (sudo спросит пароль для системной части)
# Повторный запуск безопасен (идемпотентно, существующие конфиги бэкапятся).
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KANDO_VERSION="3.0.1"
LIBSTDCXX_CONDA="https://conda.anaconda.org/conda-forge/linux-64/libstdcxx-16.2.0-h934c35e_7.conda"

log()  { echo -e "\033[1;32m[$(date +%T)]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*" >&2; }

# --- 0. Проверки окружения ---------------------------------------------------
[ "$(id -u)" -eq 0 ] && { warn "Запускать от обычного пользователя, sudo спросит сам."; exit 1; }
. /etc/os-release
log "ОС: $PRETTY_NAME"
if [ "${XDG_SESSION_TYPE:-}" != "x11" ]; then
    warn "Сессия должна быть X11 (текущая: ${XDG_SESSION_TYPE:-неизвестно}). Жесты Solaar на Wayland не работают — выберите X11-сессию на экране входа."
fi
PLASMA_VER="$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
if [ -n "$PLASMA_VER" ] && [ "${PLASMA_VER%%.*}" -ge 6 ]; then
    warn "Plasma $PLASMA_VER: дефолтных Ctrl+F10 (Present Windows) и Ctrl+F8 (сетка столов) может не быть (в Plasma 6 — Overview). После установки поправьте rules.yaml (жесты вверх/вниз) под свои комбинации."
fi

# Нужен ли libstdc++-shim для Kando (только если в системной libstdc++ нет GLIBCXX_3.4.32 — Ubuntu 22.04)
NEED_SHIM=0
strings /lib/x86_64-linux-gnu/libstdc++.so.6 2>/dev/null | grep -q 'GLIBCXX_3\.4\.32' || NEED_SHIM=1
[ "$NEED_SHIM" -eq 1 ] && log "   системный libstdc++ старее нужного — будет установлен shim (conda-forge)" \
                     || log "   системный libstdc++ достаточен — shim не нужен"

# --- 1. Системная часть (sudo) ----------------------------------------------
log "1/8 Системные пакеты и права"
sudo apt-get update -qq
sudo apt-get install -y -qq solaar curl python3-venv python3-dbus python3-gi zstd unzip >/dev/null
# AppImage нужен FUSE2; в 24.04+ пакет переименован (t64)
sudo apt-get install -y -qq libfuse2 2>/dev/null || sudo apt-get install -y -qq libfuse2t64 2>/dev/null || warn "Не установлен libfuse2/libfuse2t64 — Kando может не запуститься (AppImage)"

sudo install -m 644 "$REPO_DIR/root/99-solaar-uinput.rules" /etc/udev/rules.d/99-solaar-uinput.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add /sys/devices/virtual/misc/uinput

if ! id -nG | grep -qw input; then
    sudo usermod -aG input "$USER"
    warn "Пользователь добавлен в группу input — ПОСЛЕ установки нужен перелогин."
else
    log "   группа input уже есть"
fi

sed -e "s|__USER__|$USER|g" -e "s|__UID__|$(id -u)|g" \
    "$REPO_DIR/root/mx4-resume.hook.in" > /tmp/mx4-resume.hook
sudo install -m 755 /tmp/mx4-resume.hook /usr/lib/systemd/system-sleep/mx4-resume.hook
rm -f /tmp/mx4-resume.hook

# --- 2. Solaar 1.1.20 (venv) -------------------------------------------------
log "2/8 Solaar 1.1.20 в ~/.local/venvs/solaar"
[ -d ~/.local/venvs/solaar ] || python3 -m venv --system-site-packages ~/.local/venvs/solaar
~/.local/venvs/solaar/bin/pip install --quiet --upgrade solaar websocket-client
mkdir -p ~/.local/bin
ln -sf ~/.local/venvs/solaar/bin/solaar ~/.local/bin/solaar
log "   $(~/.local/bin/solaar --version)"

# --- 3. Kando AppImage --------------------------------------------------------
log "3/8 Kando $KANDO_VERSION (AppImage)"
mkdir -p ~/Applications
if [ ! -x ~/Applications/Kando-$KANDO_VERSION-x86_64.AppImage ]; then
    curl -fsSL -o ~/Applications/Kando-$KANDO_VERSION-x86_64.AppImage \
        "https://github.com/kando-menu/kando/releases/download/v$KANDO_VERSION/Kando-$KANDO_VERSION-x86_64.AppImage"
fi
chmod +x ~/Applications/Kando-$KANDO_VERSION-x86_64.AppImage

# --- 4. libstdc++-shim (только если системная библиотека старее: Ubuntu 22.04)
log "4/8 libstdc++ из conda-forge (shim для Kando)"
if [ "$NEED_SHIM" -eq 1 ] && [ ! -f ~/lib/conda/lib/libstdc++.so.6.0.36 ]; then
    mkdir -p ~/lib/conda /tmp/mx4-conda && cd /tmp/mx4-conda
    curl -fsSL -o stdcxx.conda "$LIBSTDCXX_CONDA"
    unzip -o -q stdcxx.conda 'pkg-*'
    tar --zstd -xf pkg-libstdcxx-*.tar.zst -C ~/lib/conda
    cd - >/dev/null && rm -rf /tmp/mx4-conda
fi

# --- 5. Файлы пользователя (скрипты, юниты, автозапуски) ----------------------
log "5/8 Скрипты, systemd-юниты, автозапуски"
BACKUP_DIR=~/backup/mx4-install-$(date +%F-%H%M%S); mkdir -p "$BACKUP_DIR"
backup_if_exists() { [ -e "$1" ] && cp -a "$1" "$BACKUP_DIR/$(basename "$1").bak" || true; }

for f in "$REPO_DIR"/bin/*; do
    dst=~/.local/bin/$(basename "$f")
    backup_if_exists "$dst"
    sed "s|__HOME__|$HOME|g" "$f" > "$dst" && chmod +x "$dst"
done
install -D -m 644 "$REPO_DIR"/systemd/* ~/.config/systemd/user/

for f in "$REPO_DIR"/autostart/*; do
    dst=~/.config/autostart/$(basename "$f")
    backup_if_exists "$dst"
    sed "s|__HOME__|$HOME|g" "$f" > "$dst"
done

# --- 6. Конфиги Solaar и Kando ------------------------------------------------
log "6/8 Конфиги (существующие бэкапятся в $BACKUP_DIR)"
mkdir -p ~/.config/solaar ~/.config/kando
backup_if_exists ~/.config/solaar/rules.yaml
sed "s|__HOME__|$HOME|g" "$REPO_DIR/solaar/rules.yaml" > ~/.config/solaar/rules.yaml
for f in menus.json config.json; do
    [ -f ~/.config/kando/$f ] && backup_if_exists ~/.config/kando/$f
    install -m 644 "$REPO_DIR/kando/$f" ~/.config/kando/$f
done

# --- 7. Запуск сервисов --------------------------------------------------------
log "7/8 Запуск сервисов"
systemctl --user daemon-reload
systemctl --user enable --now mx4-ratchet.timer >/dev/null 2>&1
systemctl --user start solaar.service
sleep 6

# --- 8. Настройки мыши (диверсия кнопок) ---------------------------------------
log "8/8 Настройки мыши"
if ~/.local/bin/solaar show 2>/dev/null | grep -q "MX Master 4"; then
    ~/.local/bin/solaar config "MX Master 4" divert-keys "Mouse Gesture Button" "Жесты мышью"
    ~/.local/bin/solaar config "MX Master 4" divert-keys "Haptic" "Жесты мышью"
    ~/.local/bin/solaar config "MX Master 4" reprogrammable-keys "Middle Button" "Mouse Middle Button"
else
    warn "Мышь не видна (уснула/выключена?) — включите её и выполните 3 команды из README (раз «Финальные шаги»)."
fi

echo
log "Готово. Проверка: systemctl --user status solaar.service, жесты и haptic-кнопка."
if ! id -nG | grep -qw input; then
    warn "Не забудьте ПЕРЕЛОГИНИТЬСЯ (группа input)."
fi

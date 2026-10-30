# mx-master-4-ubuntu

Установка [Logitech MX Master 4](https://www.logitech.com/ru-ru/products/combos/mx-master-4-wireless-mouse.html) «на максимум» на Ubuntu 22.04 (KDE Plasma, X11) без Logitech Options+.

Что получается в итоге:

- **жестовая кнопка** (под большим пальцем): вверх/вниз — все окна / сетка столов, влево/вправо — Alt+Tab, короткое нажатие — меню приложений;
- **haptic-кнопка** («Actions Ring»): радиальное меню [Kando](https://github.com/kando-menu/kando) у курсора (~0.3 с), с Terминалом, Файлами, Браузером, Скриншотом (flameshot), подменю «Окна» и «Репозитории» (VS Code с нужными репо);
- **автофиксы**: сброс трещотки при сне мыши и развал привязок после suspend ПК чинятся сами (systemd);
- средний клик, боковые кнопки, колесо, DPI, хаптика — настраиваются через [Solaar](https://github.com/pwr-Solaar/Solaar) (GUI в трее / CLI).

## Требования

- Ubuntu 22.04+ (на 22.04 для Kando ставится libstdc++-shim из conda-forge — автоматом), KDE/X11;
- мышь спарена по Bluetooth (или Logi Bolt);
- доступ в интернет (GitHub, PyPI, conda-forge, apt) и sudo.

## Установка

```bash
git clone <этот-репозиторий> && cd mx-master-4-ubuntu
bash install.sh          # спросит sudo один раз; повторный запуск безопасен
```

Затем **перелогиньтесь** (группа `input`).

### Финальные шаги, если мышь спала при установке

```bash
solaar config "MX Master 4" divert-keys "Mouse Gesture Button" "Жесты мышью"
solaar config "MX Master 4" divert-keys "Haptic" "Жесты мышью"
solaar config "MX Master 4" reprogrammable-keys "Middle Button" "Mouse Middle Button"
```

### Проверка

```bash
systemctl --user status solaar.service     # active
solaar config "MX Master 4" divert-keys    # Mouse Gesture Button и Haptic = «Перенаправлено»
systemctl --user list-timers mx4-ratchet*  # таймер трещотки
```

Дальше — руками: жесты мышью, клик по силовой кнопке под большим пальцем → пирог-меню.

## Что куда ставится

| Компонент | Файлы |
|---|---|
| Solaar 1.1.20 | `~/.local/venvs/solaar` (+ `websocket-client`), симлинк `~/.local/bin/solaar` |
| Драйвер-обвязка | `~/.local/bin/{solaar-start,kando,kando-show-menu,mx4-fix-ratchet,mx4-resume-fix}` |
| Systemd (user) | `~/.config/systemd/user/{solaar,mx4-ratchet.{service,timer},mx4-resume}.service` |
| Автозапуск | `~/.config/autostart/{solaar,kando}.desktop` |
| Конфиги | `~/.config/solaar/rules.yaml`, `~/.config/kando/{menus,config}.json` |
| Kando | `~/Applications/Kando-3.0.1-x86_64.AppImage` + `~/lib/conda` (libstdc++) |
| Root | `/etc/udev/rules.d/99-solaar-uinput.rules`, `/usr/lib/systemd/system-sleep/mx4-resume.hook` |

Существующие конфиги перед заменой бэкапятся в `~/backup/mx4-install-<дата>/`.

## Как это работает

- **Solaar** (user-сервис `solaar.service`) держит HID++ сессию с мышью: правила жестов (`rules.yaml`) и синтез клавиш через `/dev/uinput` (на него выдаются права udev-правилом). Жест срабатывает при отпускании кнопки.
- **Kando** поднимается автозапуском; его меню открывается скриптом `kando-show-menu` через WebSocket IPC (порт динамический, `~/.config/kando/ipc-info.json`) — без загрузки второго экземпляра Electron. Триггер — правило Solaar на клик haptic-кнопки (она переведена в режим «Жесты мышью»).
- **Трещотка**: режим хранится в мыши и сбрасывается при её сне — `mx4-ratchet.timer` раз в 2 минуты проверяет и возвращает (пишет только при расхождении).
- **Suspend**: слушатель Solaar умирает на disconnect мыши, а мышь сбрасывает divert-режимы. Хук `/usr/lib/systemd/system-sleep/mx4-resume.hook` после пробуждения запускает `mx4-resume.service`: перезапуск Solaar, пере-применение divert-режимов, страховка Kando. Журнал: `/tmp/mx4-resume.log`.

## Редактирование меню Kando

GUI: трей → Settings (или `kando --settings`), вкладка Menus. Правки руками — в `~/.config/kando/menus.json` (затем перезапустить Kando: `pkill -x kando; ~/.local/bin/kando &`). Команды пунктов выполняются через `/bin/sh -c`.

Чтобы добавить репозиторий VS Code: пункт с командой `code ~/путь/к/репо` (в подменю «Репозитории» уже есть примеры).

## Известные особенности

- Жесты требуют запущенный `solaar.service` и X11; на Wayland не работают.
- Имена клавиш в `rules.yaml` — строго X11-keysyms (`Control_L`, `Alt_L`, …), порядок правил — от специфичных к общим: клик-правила обязаны называть кнопку (`[Mouse Gesture Button]`, `[Haptic]`), пустой `[]` съест клик любой кнопки.
- Kando 3.0.1 на Ubuntu 22.04 требует GLIBCXX_3.4.32 — ставится shim из conda-forge (п.4 установщика). На свежих дистрибутивах не нужен.
- Средний клик слетает двумя независимыми способами: `divert-keys "Middle Button"` должно быть «Обычное», `reprogrammable-keys "Middle Button"` — «Mouse Middle Button».
- logiops не ставить параллельно с Solaar — конфликтуют за hidraw.

## Удаление

```bash
bash uninstall.sh          # пользовательская часть
bash uninstall.sh --full   # всё, включая venv/AppImage/root-файлы
```

## Ссылки

- [Solaar](https://github.com/pwr-Solaar/Solaar) · [правила Solaar](https://github.com/pwr-Solaar/Solaar/blob/master/docs/rules.md) · [issue по MX Master 4](https://github.com/pwr-Solaar/Solaar/issues/2964)
- [Kando](https://github.com/kando-menu/kando) · [IPC-интерфейс](https://kando.menu/ipc-interface)
- [logiops TESTED.md](https://github.com/PixlOne/logiops/blob/master/TESTED.md)
- [ArchWiki: Logitech MX Master](https://wiki.archlinux.org/title/Logitech_MX_Master)

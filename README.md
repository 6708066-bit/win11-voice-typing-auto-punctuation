# Windows 11: «Автоматическая расстановка знаков препинания» (Win+H) — хранилище настройки и фикс по умолчанию

Enable **Automatic punctuation** (voice typing, `Win+H`) by default on Windows 11: known MS bug resets it after reboot/hibernate, and there is no documented registry key. This repo documents where the setting actually lives (CloudStore) and ships a `.reg` fix + an optional scheduled-task script.

---

## Проблема

- Тумблер **«Автоматическая расстановка знаков препинания»** в панели голосового ввода (`Win+H`) выключен по умолчанию.
- Известный баг Windows: опция **сбрасывается после перезагрузки / гибернации** — см. [MS Q&A 3915596](https://learn.microsoft.com/en-us/answers/questions/3915596) (официального фикса у Microsoft нет, только SFC/DISM/смена профиля).
- Публично задокументированного **registry-ключа или групповой политики** для этой настройки нет ни в Microsoft Docs, ни в туториалах (tenforums, Brink и т.п. описывают только ручной клик по тумблеру).

## Где хранится настройка (находка)

```
HKCU\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\
    default$windows.data.settings.voice.voicesystemsettings\
    windows.data.settings.voice.voicesystemsettings   →  Data (REG_BINARY)
```

и зеркально:

```
HKCU\...\CloudStore\Store\DefaultAccount\Cloud\
    default$windows.data.settings.voice.voicesystemsettings\
    windows.data.settings.voice.voicesystemsettings   →  Data (REG_BINARY)
```

Значение `Data` — бинарная запись CloudStore. Меняются только **первые 5 байт timestamps** (файл Cloud) и **блок payload** (файл Current):

| Состояние | `Current\...\Data` (hex) |
|---|---|
| OFF | `434201000A0201002A06` `d7b1f5d5062a2b0e` `05 43420100` `0000000000` |
| ON  | `434201000A0201002A06` `f0c3f5d5062a2b0e` `0D 43420100` `0b0a010b020101` `0000000000` |

| Состояние | `Cloud\...\Data` (hex) |
|---|---|
| OFF | `434201000A0026` `d7b1f5d50600` |
| ON  | `434201000A0026` `f0c3f5d50600` |

Ключевой маркер ON: **длина-байт `0x05 → 0x0D`** и payload **`0b 0a 01 0b 02 01 01`** (вставлен перед 5 нулевыми байтами).

## Как найдено

1. Полный экспорт `HKCU` до клика по тумблеру: `reg export HKCU before.reg` (74,9 МБ).
2. Клик по тумблеру в UI → повторный экспорт `after.reg`.
3. Потоковый парсинг обоих файлов в map «ключ → склейка значений» (с исключением шума `SessionInfo`, `HAM`, `UserAssist`, `BagMRU` и т.п.).
4. Результат: 22 869 / 22 868 ключей, **0 ключей только-до / только-после**, 6 изменённых значений, из них **2 по теме** (Current + Cloud голосовые блобы) — остальные 4 шум (HAM, UserAssist, CloudCacheInvalidator).

Побочные результаты: `settings.dat` пакета `MicrosoftWindows.Client.CBS` **не менялся** (не место хранения); поиск по `punct|dictation|fluid` по всему HKCU/HKLM — 0 находок.

## Использование

### Вариант 1 — только `.reg`

```bat
reg import punct_ON.reg
```

### Вариант 2 — скрипт (с проверкой)

```powershell
# применить и проверить текущее состояние
powershell -ExecutionPolicy Bypass -File .\enable-auto-punctuation.ps1

# только проверить: ON / OFF
powershell -ExecutionPolicy Bypass -File .\enable-auto-punctuation.ps1 -Check
```

### Вариант 3 — авто-повтор (если настройка сбрасывается после сна/перезагрузки)

```powershell
# + задача планировщика: при входе в систему и при разблокировке экрана
powershell -ExecutionPolicy Bypass -File .\enable-auto-punctuation.ps1 -Schedule

# убрать задачу планировщика
powershell -ExecutionPolicy Bypass -File .\enable-auto-punctuation.ps1 -RemoveSchedule
```

Задача создаётся с триггерами **AtLogOn** и **SessionUnlock** (`MSFT_TaskSessionStateChangeTrigger`, `StateChange=6`) — именно на разблокировке опция обычно сбрасывается.

## Проверено на

- Windows 11 25H2, build **26200.9457** (2026-09-30)
- `reg import` — успешно, оба значения принимают ON-payload
- Долгосрочная стойкость после перезагрузки/гибернации — уточняется (см. Issues)

## Ограничения и заметки

- С **build 25300** настройки `Win+H` (auto punctuation + voice typing launcher) **синхронизируются между устройствами Microsoft-аккаунта** — настройка может «приехать» с другого ПК.
- Внутри `Data` есть FILETIME-поле — его значение меняется при каждом переключении в UI; сам payload (`0b 0a 01 0b 02 01 01`) стабилен. Скрипт проверяет именно payload, а не timestamp.
- **Откат:** просто выключите тумблер в панели `Win+H` (Windows запишет OFF-значение сама).
- Работает для `HKCU` текущего пользователя; поддержка нескольких профилей — по одному запуску на профиль.

---

## English summary

**Bug:** in Windows 11 the voice-typing toggle *Automatic punctuation* (`Win+H`) is OFF by default and Microsoft resets it after reboot/hibernate ([MS Q&A 3915596](https://learn.microsoft.com/en-us/answers/questions/3915596)). No public registry key or GPO is documented.

**Finding:** the setting is stored in the per-user CloudStore:

```
HKCU\...\CloudStore\Store\DefaultAccount\{Current|Cloud}\default$windows.data.settings.voice.voicesystemsettings\windows.data.settings.voice.voicesystemsettings  →  Data (REG_BINARY)
```

Found by diffing full `HKCU` exports taken before/after a single toggle click (22 868 keys compared, only 2 relevant values changed). The ON state = length byte `0x05 → 0x0D` plus payload **`0b 0a 01 0b 02 01 01`**.

**Fix:** `reg import punct_ON.reg`, or run `enable-auto-punctuation.ps1` (adds `-Check`, `-Schedule` for a logon+unlock scheduled task, `-RemoveSchedule`). Verified on Windows 11 25H2 build 26200.9457.
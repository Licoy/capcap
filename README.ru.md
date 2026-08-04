<p align="center">
  <img src="images/app-banner.png" alt="capcap app banner" width="760" />
</p>

<h1 align="center">capcap</h1>

<p align="center">
  Инструмент скриншотов в строке меню macOS: дважды нажмите <code>⌘</code>, чтобы сделать снимок, разметить его, собрать длинную страницу, украсить, закрепить или загрузить.
</p>

<p align="center">
  <a href="https://github.com/realskyrin/capcap/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/realskyrin/capcap?style=flat-square"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.vi.md">Tiếng Việt</a>
</p>

<p align="center">
  <a href="https://github.com/realskyrin/capcap/releases/latest">Скачать</a> ·
  <a href="https://github.com/realskyrin/homebrew-tap">Homebrew</a> ·
  <a href="CHANGELOG.md">Журнал изменений</a> ·
  <a href="https://github.com/realskyrin/capcap/issues">Issues</a>
</p>

**Быстрый способ делать, размечать и делиться скриншотами на macOS.** Дважды нажмите `⌘` из любого приложения, выберите окно или область, соберите длинный скриншот прокруткой, затем отредактируйте результат в плавающем окне. capcap живет в строке меню, не показывает Dock-иконку, не собирает телеметрию, не требует подписки и не использует сторонние зависимости. При желании можно подключить собственный хостинг изображений и копировать публичную ссылку одним кликом.

<p align="center">
  <img src="images/editor.png" alt="capcap annotation editor" width="760" />
</p>

## Почему capcap

- **Один жест для запуска**: двойное нажатие `⌘` или ваш глобальный шорткат.
- **Окно или точная область**: кликните найденное окно или выделите область с Retina-разрешением.
- **Редактируемая разметка**: стрелки, номера, текст, мозаика, маркер и перо можно менять после добавления.
- **Длинные скриншоты**: прокручивайте выбранную область, смотрите предпросмотр и продолжайте редактирование после склейки.
- **Украшение и закрепление**: фон, скругления, тень, отступы и плавающее окно поверх остальных.
- **Редактирование изображений Finder**: выберите одно изображение в Finder и откройте его в редакторе без изменения оригинала.
- **Локальная история**: быстро копируйте недавние скриншоты, цвета и ссылки из строки меню.
- **Загрузка на свой хостинг**: поддерживаются Tencent COS, Qiniu Kodo и Aliyun OSS. Учетные данные остаются на вашем Mac.
- **Чистый AppKit**: без SwiftUI, Electron и телеметрии.

## Скриншоты

<table>
<tr>
  <td width="50%" align="center"><img src="images/window-snap.png" alt="Smart window detection" /><br/><sub><b>Снимок окна в один клик</b><br/>capcap сам находит границы окна.</sub></td>
  <td width="50%" align="center"><img src="images/history.png" alt="Menu bar history" /><br/><sub><b>История в строке меню</b><br/>Повторно копируйте изображения и цвета.</sub></td>
</tr>
<tr>
  <td width="50%" align="center"><img src="images/scroll-stitch.png" alt="Scroll capture" /><br/><sub><b>Длинные страницы</b><br/>Прокручивайте и смотрите склейку вживую.</sub></td>
  <td width="50%" align="center"><img src="images/beautify.png" alt="Beautify mode" /><br/><sub><b>Украшение</b><br/>Фон, скругления, тень и отступы настраиваются.</sub></td>
</tr>
<tr>
  <td colspan="2" align="center"><img src="images/image-hosting.png" alt="Image host settings" width="520" /><br/><sub><b>Хостинг изображений</b><br/>Загрузите снимок и скопируйте публичную ссылку.</sub></td>
</tr>
</table>

## Требования

- macOS 14.0+
- Разрешение Accessibility для триггера `⌘`
- Разрешение Screen Recording для захвата через ScreenCaptureKit
- Разрешение Finder Automation для редактирования выбранного изображения

## Установка через Homebrew

```bash
brew tap realskyrin/tap
brew install --cask realskyrin/tap/capcap
```

## Предупреждение проверки macOS

Если macOS показывает предупреждение вроде `Apple не может проверить, что "capcap" не содержит вредоносного ПО`, удалите флаг quarantine у доверенного app bundle и откройте его снова:

```bash
xattr -dr com.apple.quarantine /Applications/capcap.app
```

Если вы запускаете локально собранную копию, а не приложение из `/Applications`, замените путь на фактическое расположение, например:

```bash
xattr -dr com.apple.quarantine ./build/capcap.app
```

Выполняйте эту команду только для сборок, которым доверяете: загруженных из этого репозитория или собранных вами локально.

## Сборка из исходников

```bash
./scripts/bundle.sh
```

Для локальной разработки:

```bash
bash scripts/rebuild-and-open.sh
```

## Использование

1. Дважды нажмите `⌘ Command`, используйте свой шорткат или выберите снимок в строке меню.
2. Кликните окно или выделите область.
3. Используйте плавающую панель для разметки, выбора цвета, прокрутки, украшения, сохранения, закрепления, загрузки или подтверждения.
4. Зеленая галочка или `Enter` копирует результат. `Esc` или `x` отменяет.

## Инструменты редактора

| Инструмент | Назначение |
| --- | --- |
| Прямоугольник / эллипс | Фигуры с цветом и толщиной линии |
| Стрелка | Стрелка с последующей настройкой концов и изгиба |
| Перо / маркер | Свободные линии и полупрозрачное выделение |
| Мозаика | Пикселизация чувствительных областей |
| Номер / текст | Нумерованные метки и редактируемый текст |
| Пипетка | Копирование цвета экрана как `#RRGGBB` |
| Прокрутка / украшение / закрепление / загрузка | Финальная обработка и обмен |

## Настройки

В настройках можно выбрать язык, значок строки меню, запуск при входе, демо-режим, шорткаты, размер истории, хостинг изображений и быстрые переходы к системным разрешениям. Интерфейс поддерживает 简体中文, 繁體中文, English, 日本語, 한국어, Français, Русский и Tiếng Việt.

## Лицензия

[MIT](LICENSE)

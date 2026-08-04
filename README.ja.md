<p align="center">
  <img src="images/app-banner.png" alt="capcap app banner" width="760" />
</p>

<h1 align="center">capcap</h1>

<p align="center">
  macOS のメニューバースクリーンショットツール。<code>⌘</code> をダブルタップして、撮影、注釈、スクロール結合、美化、ピン留め、アップロードまで進められます。
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
  <a href="https://github.com/realskyrin/capcap/releases/latest">ダウンロード</a> ·
  <a href="https://github.com/realskyrin/homebrew-tap">Homebrew</a> ·
  <a href="CHANGELOG.md">変更履歴</a> ·
  <a href="https://github.com/realskyrin/capcap/issues">Issues</a>
</p>

**macOS で素早くスクリーンショットを撮り、注釈を入れ、共有するためのツールです。** どこからでも `⌘` をダブルタップ。ウィンドウをクリックして撮影、範囲をドラッグ、長いページをスクロール結合し、そのまま浮動エディタで仕上げられます。Dock には表示せず、テレメトリもサブスクリプションもありません。画像ホスティングを設定すれば、ワンクリックで公開 URL をコピーできます。

<p align="center">
  <img src="images/editor.png" alt="capcap annotation editor" width="760" />
</p>

## capcap の特徴

- **ショートカットひとつで起動**：`⌘` のダブルタップ、または設定したグローバルショートカットで開始できます。
- **ウィンドウ撮影と範囲撮影**：ウィンドウにホバーしてクリック、または任意の範囲を Retina 解像度で撮影できます。
- **編集できる注釈**：矢印、番号、テキスト、モザイク、蛍光ペン、ペンは配置後も移動、回転、変更、取り消しができます。
- **スクロール撮影**：選択範囲内をスクロールしながらフレームを結合し、結果をそのまま編集できます。
- **美化とピン留め**：角丸、影、余白、グラデーションや壁紙背景を加えたり、画像を前面に固定できます。
- **Finder の画像を直接編集**：Finder で画像を 1 つ選択して同じショートカットを押すと、元ファイルを変更せずにエディタで開けます。
- **メニューバー履歴**：最近のスクリーンショット、抽出した色、アップロード URL をローカルに保持し、すぐ再コピーできます。
- **自分の画像ホストへアップロード**：Tencent COS、Qiniu Kodo、Aliyun OSS を設定できます。資格情報は Mac 上にのみ保存されます。
- **純粋な AppKit 実装**：SwiftUI、Electron、外部依存なしで小さく高速に動きます。

## スクリーンショット

<table>
<tr>
  <td width="50%" align="center"><img src="images/window-snap.png" alt="Smart window detection" /><br/><sub><b>ウィンドウをクリックして撮影</b><br/>capcap がウィンドウ境界を自動検出します。</sub></td>
  <td width="50%" align="center"><img src="images/history.png" alt="Menu bar history" /><br/><sub><b>メニューバー履歴</b><br/>最近の画像や色をすぐ再コピーできます。</sub></td>
</tr>
<tr>
  <td width="50%" align="center"><img src="images/scroll-stitch.png" alt="Scroll capture" /><br/><sub><b>長いページを結合</b><br/>スクロールしながらライブプレビューで結合します。</sub></td>
  <td width="50%" align="center"><img src="images/beautify.png" alt="Beautify mode" /><br/><sub><b>ワンクリック美化</b><br/>背景、角丸、影、余白を調整できます。</sub></td>
</tr>
<tr>
  <td colspan="2" align="center"><img src="images/image-hosting.png" alt="Image host settings" width="520" /><br/><sub><b>画像ホスト連携</b><br/>設定済みプロバイダへアップロードし、公開 URL をクリップボードへコピーします。</sub></td>
</tr>
</table>

## 要件

- macOS 14.0 以降
- アクセシビリティ権限：`⌘` ダブルタップの検出に使用
- 画面収録権限：ScreenCaptureKit による撮影に使用
- Finder のオートメーション権限：選択済み画像を編集するときに使用

## Homebrew でインストール

```bash
brew tap realskyrin/tap
brew install --cask realskyrin/tap/capcap
```

## macOS の検証警告

macOS に `Appleは "capcap" にマルウェアが含まれていないことを検証できません` のような警告が表示される場合は、信頼できるアプリバンドルから quarantine フラグを削除してから、もう一度開いてください。

```bash
xattr -dr com.apple.quarantine /Applications/capcap.app
```

`/Applications` 内のアプリではなくローカルでビルドしたコピーを実行している場合は、実際の場所にパスを置き換えてください。例：

```bash
xattr -dr com.apple.quarantine ./build/capcap.app
```

このコマンドは、このリポジトリからダウンロードしたビルドや自分でビルドしたものなど、信頼できるビルドに対してのみ実行してください。

## ソースからビルド

```bash
./scripts/bundle.sh
```

ローカル開発では次のスクリプトで再ビルド、旧プロセス終了、起動確認まで行えます。

```bash
bash scripts/rebuild-and-open.sh
```

## 使い方

1. `⌘ Command` をダブルタップ、カスタムショートカットを押す、またはメニューバーからスクリーンショットを選びます。
2. ウィンドウをクリックして撮影するか、任意の範囲をドラッグします。
3. 浮動ツールバーで注釈、色抽出、スクロール撮影、美化、保存、ピン留め、アップロード、確認を行います。
4. 緑のチェックまたは `Enter` で結果をクリップボードへコピーします。`Esc` または `x` でキャンセルできます。

## エディターツール

| ツール | 内容 |
| --- | --- |
| 矩形 / 楕円 | 色と線幅を選んで図形を描画 |
| 矢印 | 直線矢印を描画し、あとから端点やカーブを調整 |
| ペン / 蛍光ペン | フリーハンド線や半透明マーカーを描画 |
| モザイク | 機密部分をピクセル化 |
| 番号 / テキスト | 番号付き吹き出しや編集可能なテキストを追加 |
| スポイト | 任意の画面色を `#RRGGBB` としてコピー |
| スクロール撮影 / 美化 / ピン留め / アップロード | 仕上げと共有のための補助ツール |

## 設定

設定では、言語、メニューバーアイコン、ログイン時起動、デモモード、ショートカット、履歴サイズ、画像ホスト、権限ショートカットを変更できます。UI 言語は简体中文、繁體中文、English、日本語、한국어、Français、Русский、Tiếng Việt に対応しています。

## ライセンス

[MIT](LICENSE)

# Windowsでの導入

まず [共通導入ガイド](COURSE_GUIDE.md) を上から進めます。Macの人は [Mac版](MAC_SETUP.md) を使ってください。

## 講義での進め方

1. [OpenAI公式アプリ案内](https://learn.chatgpt.com/docs/app) からWindows向けアプリを導入し、ログインします。Codexを使う画面を選びます。
2. 配布ZIPを右クリックして「すべて展開」。ZIP内のまま起動しません。
3. 展開したAI-NORIKO-Starter-KitフォルダをCodexで開きます。START_HERE.mdが見えることを確認します。
4. [セットアップ依頼](../CODEX_SETUP_PROMPT.md) を貼り、診断結果を待ちます。Node.jsは24 LTS推奨です（24.14.0でMac検証、最低22.12.0以上）。未導入なら [公式サイト](https://nodejs.org/) から本人が導入します。
5. 初回設定後、手動タスクを1件登録・完了します。自由な相談はAIモデルとサンプルナレッジも設定します（P03・P04）。
6. 主催者から思考パックを受け取る場合は、[NORIKOナレッジの導入](NORIKO_KNOWLEDGE_SETUP.md) とP21へ進みます。DocumentsがOneDriveへ移動されている場合も、NORIKO設定画面の実際の保存先を確認します。

## 起動ファイルを使う場合

START-WINDOWS.bat を開きます。Defender等の警告が出たら配布元と内容を確認し、講師または管理者へ相談します。保護機能の無効化・会社の制限回避はしません。

PowerShellまたはコマンドプロンプトを使える方は、キットフォルダ内で次を実行します。

```text
npm install
npm run doctor
npm run check
npm run build
npm run smoke
npm run start
```

npm.ps1等の実行制限が出た場合は、そのエラーをCodexへ伝えます。実行ポリシーを一律に緩めず、管理者の方針内で対応します。

Node.js導入直後に「見つからない」と出る場合は、ターミナルとCodexを閉じて開き直し、診断を再実行します。PowerShellのスクリプト制限がある端末は、許可された環境で `npm.cmd` を使う方法を講師に確認してください。会社の管理制限は回避しません。

## 任意の接続

- AI作業のCLI連携は、デスクトップアプリへのログインとは別です。使うCLIの公式手順でログインして状態を確認します。本キットはcodex.cmdの検出にも対応しています。
- OllamaはWindows向け導入手順とPCの空き容量を確認します。モデル名を設定と一致させます。
- ローカル音声認識にはFFmpeg、whisper-cli.exe、モデルが必要です。NORIKO_FFMPEG、NORIKO_WHISPER_CLI、NORIKO_WHISPER_MODELで場所を指定できます。
- Google・Fish Audioは任意です。Windowsでも本人のアカウントで接続します。

## 動作確認と常駐

OS別の起動経路は用意されていますが、ご自身のWindows端末でも確認してください。Macでの検証だけをWindows実機確認とは扱いません。常駐・タスクバー・ログイン時起動はP18の追加開発で、完成済みインストーラーではありません。

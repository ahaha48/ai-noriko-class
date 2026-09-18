# Macでの導入

まず [共通導入ガイド](COURSE_GUIDE.md) を上から進めます。Windowsの人は [Windows版](WINDOWS_SETUP.md) を使ってください。

## 講義での進め方

1. [OpenAI公式アプリ案内](https://learn.chatgpt.com/docs/app) から対応アプリを導入し、ログインします。Codexを使う画面を選びます。
2. 配布ZIPを展開し、AI-NORIKO-Starter-KitフォルダをCodexで開きます。START_HERE.mdが見えることを確認します。
3. [セットアップ依頼](../CODEX_SETUP_PROMPT.md) を貼り、診断結果を待ちます。Node.jsは24 LTS推奨です（24.14.0で検証、最低22.12.0以上）。未導入なら [公式サイト](https://nodejs.org/) から本人が導入します。
4. 初回設定を行い、手動タスクを1件登録・完了します。
5. 自由な相談も試す場合は、AIモデルとサンプルナレッジを設定します（P03・P04）。
6. 主催者から思考パックを受け取る場合は、[NORIKOナレッジの導入](NORIKO_KNOWLEDGE_SETUP.md) とP21へ進みます。自分の保管庫を配布元フォルダと混同しません。

## 起動ファイルを使う場合

START-MAC.command をFinderから開きます。配布元・内容が不明なファイルは実行せず、セキュリティ警告が出たら講師へ確認します。保護機能を一括無効化しません。

ターミナルを使える方は、キットフォルダ内で次を実行します。

```text
npm install
npm run doctor
npm run check
npm run build
npm run smoke
npm run start
```

## 任意の接続

- AI作業のCLI連携は、デスクトップアプリへのログインとは別です。使うCLIの公式手順でログインして状態を確認します。
- Ollamaは端末性能とモデル容量を確認してから導入します。設定されたモデル名と実際のモデル名を揃えます。
- ローカル音声認識にはFFmpeg、whisper.cppのwhisper-cli、モデルが必要です。必要に応じNORIKO_FFMPEG、NORIKO_WHISPER_CLI、NORIKO_WHISPER_MODELで場所を指定できます。
- GoogleとFish Audioは必須ではありません。料金画面、ログイン、権限付与は本人が確認します。

## 終了・再起動

本キットは開発用起動です。ターミナル終了やPC再起動で終了する場合があります。常駐・Dock・ログイン時起動はP18の追加開発です。講師個人用アプリの常駐設定と同一ではありません。

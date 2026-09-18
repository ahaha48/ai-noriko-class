# AI NORIKO 生徒用講義ページ

講義の導入手順、21本のコピペ用プロンプト、スターターキット、講義スライド、NORIKOナレッジ導入ガイドを公開する静的サイトです。

GitHub Pagesの公開元は `main` ブランチの `/docs`。生徒用ページがトップに開き、ログインなしで資料をダウンロードできます。`/resources/` からも同じ教材を開けます。

公開用として確認した教材のみを含みます。思考パック本体、個人のObsidian、認証情報、音声IDは含みません。教材の掲載は、再配布や商用利用の新たな許諾を与えるものではありません。

Windows向けに、ZIPのダウンロード・SHA-256照合・安全な新規フォルダへの展開だけを行う `AI-NORIKO-Windows-Setup.cmd` を配布します。アプリや追加ソフトは起動・導入せず、既存ファイルは上書きしません。OSの保護や実行ポリシーは変更しません。ブラウザや管理設定で実行が止まるPCは手動ZIPまたは講師の案内を使います。

## 更新する方へ

講義の元プロジェクト、AI-NORIKO-Starter-Kit、AI-NORIKO-Learning-Guideを同じ親フォルダに置き、元プロジェクトの依存を準備します。キット本体・資料・プロンプトの検証と同期が済んだら、`python3 scripts/package-downloads.py`、`node scripts/export.mjs` の順に実行します。出力先は `docs` です。既存のSitesサイトや個人アプリは変更しません。

キットv1.2.0は実際の本体フォルダのパスから環境IDを作り、ローカル保存先とElectronセッションを環境別に分けます。保存先の説明は `docs/downloads/guide/docs/MULTIPLE_INSTALLS.md` を参照してください。移動・改名後の自動移行や、同じ外部アカウントのデータ分離は行いません。

パッケージ処理は許可したソースと教材のみを収録し、CRC・秘密情報パターンを検査します。`kit-files.json` は全ファイルのサイズとSHA-256、`release.json` は版番号と不変の配布URLを記録します。講義スライドは9月18日版を維持し、複数導入と保存先は最新版ガイドを優先する旨をページに明記しています。

公開前にコピー操作・教材リンク・スマホ表示と、公開対象に秘密情報がないことを確認してください。実アカウントの接続や個人情報は公開用フォルダへ入れません。

Windows補助ファイルは `scripts/windows-setup.cmd.in` から生成します。export時にキットZIPのSHA-256と版ごとの不変URLを埋め込むため、ZIP更新時は補助ファイルも必ず再生成します。Windowsの自動テストは `.github/workflows/windows-setup-test.yml`、ページの確認は `scripts/verify.mjs`。公開前はコミット済みZIPをローカルHTTPで配信し、公開後はworkflow_dispatchのlive検証で実URLを確認します。自動テストでは `AI_NORIKO_SETUP_NONINTERACTIVE=1` で最後のExplorer表示と一時停止だけを省略し、取得・照合・展開処理は同じものを使います。

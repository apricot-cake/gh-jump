# 技術スタックの選定

調査日: 2026-10-04。PowerToys Run のプラグインではなく、PowerToys Command Palette の拡張を対象にした。

## 実装方式の比較

| 方式 | 公式の位置付け・採用実績 | 判断 |
| --- | --- | --- |
| C# / .NET + Command Palette SDK / Toolkit | 公式開発手順とテンプレートが提供され、Microsoft公式GitHub拡張もC#で実装されている | 採用 |
| JavaScript / TypeScript | PowerToysのロードマップではv0.102の開発項目。C#と同等の安定した配布経路・採用実績は今回確認できなかった | 見送り |
| WinUIで独自画面を作る | 今回の一覧・ページ遷移はCommand Paletteの標準ページで表現できる | 独自画面は作らない |

拡張は別プロセスのCOMサーバーとして動き、WinRTのSDKインターフェイスでCommand Paletteへページとコマンドを提供する。公式テンプレートのCOMサーバー構成を使い、Windows SDKでMSIXを作成する。今回のリスト画面ではWindows App SDKへの直接依存やWinUI/XAMLの実装は不要だった。

根拠: [公式開発手順](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/creating-an-extension)、[拡張モデル](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/extensibility-overview)、[Microsoft公式GitHub拡張](https://github.com/microsoft/CmdPalGitHubExtension)、[PowerToysロードマップ](https://github.com/microsoft/PowerToys#roadmap)。

## 採用構成

| 項目 | 選定と理由 |
| --- | --- |
| 言語・ランタイム | C# / .NET 10。公式SDKと同じ言語を使い、Nullableと標準Analyzerで型・品質を確認する |
| Command Palette API | Microsoft公式SDK / Toolkit。標準のリストページと検索を使い、API変更への追従範囲を絞る |
| GitHub API | GitHub CLIの `gh api`。公式の認証付きREST / GraphQL呼び出し機能を利用する |
| 認証 | GitHub CLIの既存ログイン。拡張はトークンを取り出さず、認証・保管はCLIへ任せる |
| アイコン | GitHub公式Octiconsの必要なSVGだけ同梱。実行時ライブラリを増やさない |
| テスト | xUnit。API応答・外部プロセス・時間・キャッシュを差し替え、ロジックを検証する |
| 整形・静的解析 | `.editorconfig`、`dotnet format`、.NET SDK標準Analyzer |
| 配布 | MSIX。開発用登録と配布用パッケージを区別する |

GitHub APIクライアントにはOctokit.NET、`HttpClient`による直接呼び出し、`gh api`を比較した。Octokit.NETはGitHub公式の型付きSDKで、Microsoft公式GitHub拡張でも使われる。GH JumpはCLI利用者向けの一覧取得とURL移動に範囲を絞るため、認証を再利用できる `gh api` を選ぶ。トークンを取り出してOctokitへ渡す方式は採用しない。

`gh api`はGitHub公式のREST API入門で案内され、pagination、JSON、明示的なHTTPメソッドを提供する。エディター拡張Octo.nvimにも利用実績がある。ただし、Command Palette拡張全体で主流と断言できる根拠はない。外部プロセスの終了・キャンセル・タイムアウトとJSONモデルの検証はGH Jumpで扱う。

根拠: [GitHub REST Quickstart](https://docs.github.com/en/rest/quickstart?tool=cli)、[`gh api`](https://cli.github.com/manual/gh_api)、[Octokit.NET](https://github.com/octokit/octokit.net)、[Octo.nvimのCLI呼び出し](https://github.com/pwntester/octo.nvim/blob/master/lua/octo/gh/init.lua)、[Octicons](https://primer.style/octicons/)。

## 認証の比較

| 方式 | 負担・制約 | 判断 |
| --- | --- | --- |
| Microsoft公式GitHub拡張のOAuth | 専用アプリ登録、認可コード処理、トークン保存を拡張で管理する | 参考にするが共用しない |
| Command Paletteの共有GitHub認証 | 公開SDKで共有する仕組みは今回確認できなかった | 使用しない |
| `gh api` | CLIと認証・権限・アカウントを共有する。CLI導入が前提 | 採用 |
| OAuth Device Flow | Client Secretは不要だが、アプリ登録とコード表示・ポーリング・資格情報保存が必要 | 現時点では不要 |
| PAT入力 | 入力・保存・更新をユーザーに求める | 初期方式にしない |

GitHub CLIは通常OSの資格情報ストアへ保存するが、利用できないと平文ファイルへフォールバックする。GH Jumpは平文保存を促さず、ログイン案内に保存方式の確認を含める。`gh api`でもCLIが持つ権限をGH Jump専用に縮小することはできない。OAuth Appの `repo` スコープもprivateリポジトリの読み取りだけに制限された権限ではない。

根拠: [公式拡張のOAuth実装](https://github.com/microsoft/CmdPalGitHubExtension/blob/main/GitHubExtension/DeveloperId/OAuthRequest.cs)、[公式拡張の資格情報保存](https://github.com/microsoft/CmdPalGitHubExtension/blob/main/GitHubExtension/DeveloperId/CredentialVault.cs)、[CLIログイン](https://cli.github.com/manual/gh_auth_login)、[Device Flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)、[OAuthスコープ](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps)。

## リポジトリ取得と画面遷移

RESTの `/user/repos` はowner、collaborator、organization_memberのリポジトリを対象にできる。全ページを取得し、privateとforkを除外しない。取得済みデータをローカルで検索し、入力ごとのAPI呼び出しは行わない。トークンの権限やorganizationのポリシーにより取得範囲は変わる。

PR作成は `/compare` を開く。ベース・比較ブランチの情報がない状態では、GitHub標準の比較画面から選択する。Issue作成は `/issues/new` を開く。

根拠: [リポジトリ一覧API](https://docs.github.com/en/rest/repos/repos#list-repositories-for-the-authenticated-user)、[PR作成手順](https://docs.github.com/en/pull-requests/how-tos/create-pull-requests/creating-a-pull-request)。

## 配布とGallery

Microsoftの公開ガイドはMicrosoft Storeを推奨する。WinGetも対応し、`windows-commandpalette-extension` タグで拡張を発見できる。GalleryはMSIXの保管先ではなく、StoreまたはWinGetのインストール先を登録するディレクトリである。

GH Jumpはまずprivateリポジトリで開発する。将来公開する場合はMSIXの識別子・publisher・署名と配布先を確定し、その後Galleryに登録する。非公開開発用の登録やCI成果物だけで公開済みとは扱わない。

根拠: [公式公開ガイド](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/publish-extension)、[Gallery投稿手順](https://github.com/microsoft/CmdPal-Extensions/blob/main/docs/CONTRIBUTING.md)。

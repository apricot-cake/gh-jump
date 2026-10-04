# GH Jump

GitHubのリポジトリを選び、トップページ、Issues、Pull requests、Actionsなどへ移動するPowerToys Command Palette拡張です。GitHub CLIでログイン済みの開発者を対象にしています。

## 基本操作

Command PaletteでGH Jumpを開き、リポジトリ名、owner名、`owner/repository`で絞り込みます。一覧はリポジトリ名を主表示、ユーザー名・organization名をサブ表示にします。Enterでリポジトリを選ぶと、アクション一覧が表示されます。空入力のEnterはリポジトリトップを開きます。候補が一つになっても自動実行しません。

呼び出し用の `gh` はCommand Paletteの標準エイリアス設定で登録します。リポジトリ名やアクション名の検索文字とは別の設定です。

| 操作例 | 開く画面 |
| --- | --- |
| GH Jump → `owner/repo` → Enter → Enter | リポジトリトップ |
| GH Jump → `owner/repo` → Enter → `i` → Enter | Issues |
| GH Jump → `owner/repo` → Enter → `a` → Enter | Actions |
| GH Jump → `owner/repo` → Enter → `p` → Enter | Pull requests |
| GH Jump → `owner/repo` → Enter → `c` → Enter → `i` → Enter | Issue作成 |
| GH Jump → `owner/repo` → Enter → `c` → Enter → `p` → Enter | PR作成の比較画面 |

## アクション

アクションにはGitHub公式Octiconsを使用します。`Create`だけが子ページへ移動し、それ以外は既定ブラウザーでGitHubを開き、パレットを閉じます。

| アクション | URLの末尾 | アイコン |
| --- | --- | --- |
| Repository top | なし | repo |
| Issues | `/issues` | issue-opened |
| Pull requests | `/pulls` | git-pull-request |
| Actions | `/actions` | workflow |
| Releases | `/releases` | tag |
| Security | `/security` | shield |
| Settings | `/settings` | gear |
| Create → Issue | `/issues/new` | issue-opened |
| Create → Pull request | `/compare` | git-pull-request |

PR作成ではベースと比較ブランチをGitHub側で選びます。SettingsやSecurityの閲覧・変更権限はGitHub側で判定されます。

## 認証

GitHub CLIをインストールし、ブラウザー経由でログインします。

```powershell
winget install --id GitHub.cli --exact
gh auth login --hostname github.com --web
gh auth status --hostname github.com
```

GitHub CLIは通常Windowsの資格情報ストアへトークンを保存します。ストアが利用できないと平文へフォールバックするため、`gh auth status`で保存方式を確認してください。平文保存を選ぶ `--insecure-storage` は使用しません。[CLIの認証仕様](https://cli.github.com/manual/gh_auth_login)

GH Jumpは `gh api` に取得を任せ、`gh auth token`でトークンを取り出しません。独自OAuthアプリやPAT入力は不要です。CLIと認証・権限・使用アカウントを共有します。アカウントを切り替える場合はCLIで切り替え、GH Jumpで一覧を更新してください。

`GH_TOKEN` または `GITHUB_TOKEN` が環境変数に設定されていると、CLIは保存済みの認証よりその値を優先します。GH Jumpを起動する環境でも、意図したアカウントが使われているか確認してください。[CLIの環境変数](https://cli.github.com/manual/gh_help_environment)

## リポジトリ一覧

自分のリポジトリ、collaboratorとしてアクセスできるリポジトリ、organization所属によってアクセスできるリポジトリを取得します。privateとforkも含みます。全ページを取得し、入力時は取得済み一覧を検索します。キー入力ごとにAPIへ問い合わせません。

キャッシュはアカウントごとに分離します。キャッシュにはprivateリポジトリの名前も含まれるため、共有Windowsアカウントでの利用には適しません。認証切れや権限変更の後は再ログイン・更新が必要です。

## インストール

ソースコードを公開しています。Store、WinGet、Extension Galleryには公開していません。

Windows 11でPowerToysのCommand PaletteとGitHub CLIを有効にしてください。開発用の登録と配布用MSIXのインストールは異なります。開発用登録はWindowsの開発者モードを有効にして行います。配布用MSIXは信頼できる証明書の署名が必要です。CIが作る未署名パッケージを、そのまま一般利用者へ配布することはできません。

ビルド後、次の手順で開発用登録します。

```powershell
./scripts/Register-Dev.ps1 -Architecture x64
```

Command Paletteで拡張を再読み込みし、GH Jumpを開いてください。Command Paletteのエイリアス設定でGH Jumpに `gh` を登録すると、以後は `gh` で呼び出せます。

## 技術スタック

| 用途 | 技術 |
| --- | --- |
| 拡張本体 | C# / .NET 10 |
| ページ・コマンド | Microsoft公式Command Palette SDK / Toolkit |
| 登録・配布 | WinRT / COM、Windows SDK、MSIX |
| GitHub API・認証 | GitHub CLI `gh api` |
| JSON | `System.Text.Json` |
| アイコン | GitHub Octicons |
| テスト | xUnit |
| 整形・静的解析 | `.editorconfig`、`dotnet format`、.NET SDK Analyzer |

Microsoft公式の拡張方式と標準ページを採用し、独自UIや認証を作らない構成にしています。GitHub APIはCLIへ任せ、拡張内へのトークン持ち込みとSDK依存を減らします。調査日、比較した案、公式資料は[技術スタックの選定](docs/stack-research.md)に記載しています。

## ビルド・開発

必要な環境は.NET 10 SDK、Windows SDK、Windows 11、PowerToysです。プロジェクト内のSDK指定は `global.json` を参照してください。

```powershell
./scripts/Verify.ps1 -Configuration Release -Architecture x64
```

検証スクリプトでビルド、unit test、整形・Analyzer、MSIXパッケージ検証を実行します。パッケージの出力先は `artifacts/packages` です。GitHub Actionsでも同じスクリプトを実行します。

NuGetの取得元は `NuGet.Config` でnuget.orgに固定しています。CIはGitleaksによる秘密情報検査と、PRのDependency Reviewも実行します。NuGetとGitHub Actionsの更新はDependabotが週次で提案します。Command Palette SDKの更新はホストとの互換性を確認して取り込みます。

実装はCommand Palette本体の `src/GHJump`、取得・キャッシュ・アクション・URLのロジックを扱う `src/GHJump.Core` に分けています。`tests/GHJump.Core.Tests` と `tests/GHJump.Extension.Tests` でロジックと公式Toolkitの検索を検証します。アクションを増やす場合はアクション定義へ項目を追加します。

登録済み拡張の実データ取得とページ構成は、次のコマンドでも確認できます。

```powershell
./scripts/Verify-Activation.ps1 -LoadRepositories
```

## 制限事項

- GitHub.comを対象にします。GitHub Enterprise Serverは対象外です。
- GitHub CLIのインストールと有効なログインが必要です。
- 一覧に出る範囲はCLIのトークン権限、organizationのSSO・OAuth制限に依存します。
- 初回取得や更新では通信が必要です。キャッシュの内容は最新の権限を保証しません。
- ブラウザーのGitHubログインとCLIのアカウントは別です。移動先のアクセスにはブラウザー側でも適切なログインが必要です。
- MSIX検証と自動テストだけでは、Command Palette上の操作確認を代替できません。

## ライセンス

GH Jumpの独自コードは[MIT License](LICENSE)です。第三者ソフトウェアにはそれぞれのライセンスを適用します。[第三者通知](licenses/THIRD-PARTY-NOTICES.md)と各ライセンス原文はMSIXにも含め、パッケージ検証で同梱と内容の一致を確認します。

## Extension Galleryへの公開

公開を決めた場合は、まずMSIXのpublisher・identityを確定し、Microsoft StoreまたはWinGetで配布します。Microsoftの推奨経路はStoreです。WinGetでは `windows-commandpalette-extension` タグを付けます。[公式公開ガイド](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/publish-extension)

Galleryは配布物を保管せず、StoreまたはWinGetのインストール先へリンクします。配布先を用意した後、`microsoft/CmdPal-Extensions`へアイコンと `extension.json` を追加するPRを送ります。ソースを非公開にしたままでも、公開インストール先と利用者向けの案内は必要です。[Gallery投稿手順](https://github.com/microsoft/CmdPal-Extensions/blob/main/docs/CONTRIBUTING.md)

## 検証状態

Windows 11 / Command Palette 0.11.11762.0で、ビルド・Analyzer・整形、53件の自動テスト、MSIX作成・検証、COM経由の拡張起動・リポジトリ取得・ページ構成を確認しました。実アカウントの8件中5件のprivateリポジトリを取得できました。organization・fork・pagination・認証切れ・API失敗・キャッシュは自動テストで検証しています。実アカウントにはorganization・forkがないため、その実データ確認は未実施です。

公式Toolkitによる500件の検索は、200回の平均で約0.63msでした。Command Palette本体でのキー入力からブラウザーが開くまでの操作は未確認です。

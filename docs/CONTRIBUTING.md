# CONTRIBUTING.md

開発環境、ビルド、検証、開発用登録、配布について説明します。認証と操作は[使い方](使い方.md)を参照してください。コマンドはリポジトリのルートで実行します。

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

Microsoft公式の拡張方式と標準ページを採用し、独自UIや認証を作らない構成にしています。GitHub APIはCLIへ任せ、拡張内へのトークン持ち込みとSDK依存を減らします。

## ビルドと検証

必要な環境は.NET 10 SDK、Windows SDK、Windows 11、PowerToysです。プロジェクト内のSDK指定は `global.json` を参照してください。

```powershell
./scripts/Verify.ps1 -Configuration Release -Architecture x64
```

検証スクリプトでビルド、unit test、整形・Analyzer、MSIXパッケージ検証を実行します。パッケージの出力先は `artifacts/packages` です。GitHub Actionsでも同じスクリプトを実行します。

NuGetの取得元は `NuGet.Config` でnuget.orgに固定しています。CIはGitleaksによる秘密情報検査と、PRのDependency Reviewも実行します。NuGetとGitHub Actionsの更新はDependabotが週次で提案します。Command Palette SDKの更新はホストとの互換性を確認して取り込みます。

実装はCommand Palette本体の `src/GHJump`、取得・キャッシュ・アクション・URLのロジックを扱う `src/GHJump.Core` に分けています。`tests/GHJump.Core.Tests` と `tests/GHJump.Extension.Tests` でロジックと公式Toolkitの検索を検証します。アクションを増やす場合はアクション定義へ項目を追加します。配布物に含まれる第三者ソフトウェアのライセンスは[第三者通知](../licenses/THIRD-PARTY-NOTICES.md)を参照してください。

登録済み拡張の実データ取得とページ構成は、次のコマンドでも確認できます。

```powershell
./scripts/Verify-Activation.ps1 -LoadRepositories
```

### Command Palette上のE2E

実際のキー入力、ページ遷移、ブラウザーのURL、パレット終了はwinapp CLIで検証します。ロックを解除したWindowsのデスクトップ、登録済みGH Jump、ログイン済みGitHub CLIが必要です。検証中はパレットとブラウザーが前面に出ます。

```powershell
winget install --id Microsoft.WinAppCli --exact --source winget
./scripts/Verify-UI.ps1
```

このスクリプトはwinapp CLI 0.7.1を対象にしています。呼び出しキーの既定値はAlt＋Spaceです。Command Paletteで別のキーを設定している場合は、`-ActivationShortcut 'win+alt+space'`などで指定してください。`gh`検索でGH Jumpが先頭候補になることも検証します。

対象は`apricot-cake/gh-jump`です。別のリポジトリを使う場合は`-Repository 'owner/repository'`を指定します。トップ、Issues、Actions、Pull requests、Create → Issue、Create → Pull requestの6経路を確認します。作成画面を開くところまでで、IssueやPRは投稿しません。

一つの経路だけを確認する場合は`-Scenario Top`などを指定します。各経路の実行前に、開いているブラウザーウィンドウのアドレス欄を確認します。遷移先と同じURLが表示されている場合だけ、そのタブを`about:blank`へ移動し、実行前後の変化を確認できるようにします。結果は`artifacts/e2e`のJSONへ保存します。取得したリポジトリ一覧やブラウザーのページ本文、実行前のURLは保存しません。失敗や環境の制約による中断は成功として扱いません。

ブラウザーのURLはChrome、Edge、Firefoxの各ウィンドウで表示中のタブのアドレス欄から読み取ります。前面に来ることは成功条件に含めません。ブラウザーの言語やUI構成によりアドレス欄を取得できない場合は失敗します。段階ごとのページ名、入力の一致、候補数、選択状態、経過時間もJSONに記録します。対話型デスクトップを必要とするため、通常のCIには含めていません。[winappのUI Automation仕様](https://github.com/microsoft/winappCli/blob/main/docs/ui-automation.md)を参照してください。

## 開発用に登録する

ソースコードを公開しています。Store、WinGet、Extension Galleryには公開していません。

Windows 11でPowerToysのCommand PaletteとGitHub CLIを有効にしてください。開発用の登録と配布用MSIXのインストールは異なります。開発用登録はWindowsの開発者モードを有効にして行います。配布用MSIXは信頼できる証明書の署名が必要です。CIが作る未署名パッケージを、そのまま一般利用者へ配布することはできません。

上記の検証スクリプトでビルドとパッケージ作成を終えた後、次の手順で開発用登録します。

```powershell
./scripts/Register-Dev.ps1 -Architecture x64
```

登録スクリプトは登録後にCommand Paletteを再起動します。修正を反映するときも、ビルドとパッケージ作成後にこのスクリプトを実行してください。Command Paletteのエイリアス設定でGH Jumpに `gh` を登録すると、以後は `gh` で呼び出せます。

## Microsoft Storeへの提出

配布先はMicrosoftが推奨するMicrosoft Storeです。提出にはPartner Centerの登録、名前の予約、割り当てられたパッケージ識別情報の反映が必要です。パッケージの構造検証とStoreの審査は別に行います。[公式公開ガイド](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/publish-extension)

### 名前とパッケージ識別情報

[Partner Center](https://partner.microsoft.com/)で開発者登録し、Apps and gamesからMSIX製品を作成して`GH Jump`の名前を予約します。Product management → Product identityに表示される次の3項目を取得します。値は省略・推測せず、そのまま使用してください。

| Partner Centerの項目 | manifestの反映先 |
| --- | --- |
| Package/Identity/Name | `Package/Identity/@Name` |
| Package/Identity/Publisher | `Package/Identity/@Publisher` |
| Package/Properties/PublisherDisplayName | `Package/Properties/PublisherDisplayName` |

`src/GHJump/Package.appxmanifest`のidentityをこの値へ揃え、DisplayNameを予約した製品名と一致させます。開発用identityから変更するとWindows上で別パッケージになるため、開発用登録との重複を解消してから操作を確認します。[Command Palette拡張のStore提出手順](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/publish-extension-store)

Store用のバージョンは4区切りとし、末尾を`0`にします。先頭は`1`以上、それぞれの数値は`65535`以下です。例は`1.0.0.0`です。公開後の更新は既存の公開版より大きいバージョンを使用します。[MSIXパッケージの要件](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/app-package-requirements?pivots=store-installer-msix)

### 提出用パッケージ

次のスクリプトでx64とARM64のMSIXを作り、1つのMSIXbundleへまとめます。manifestのidentityとバージョンをそのまま使用します。

```powershell
./scripts/Package-Bundle.ps1 -Configuration Release
```

出力先は`artifacts/packages/GHJump_<Version>_Bundle.msixbundle`です。Windows SDKのMakeAppxで構造と展開後の内容を検証します。GitHub Actionsでもbundleを検証します。Storeへ提出するbundleは、割り当てられたidentityとStore用バージョンをmanifestへ反映した後に作成します。提出前に各アーキテクチャの実機でインストール・起動・操作を確認してください。

Storeは審査通過後にMSIXへ署名します。Store提出のために配布用証明書を購入したり、このリポジトリへ署名鍵を保存したりする必要はありません。Store以外から一般配布するMSIXには、別途信頼できる署名が必要です。[Microsoft Storeの署名](https://learn.microsoft.com/en-us/windows/apps/publish/faq/get-started-with-the-microsoft-store)

### 掲載内容と審査

Partner CenterのPackagesへbundleをアップロードします。パッケージの言語は`en-us`です。English (United States)のDescriptionには、次の説明案を使用できます。

> GH Jump integrates with the Windows Command Palette to help you find GitHub repositories and open their pages using your keyboard. Search by repository name, owner, or owner/repository. Open the repository home page, Issues, Pull requests, Actions, Releases, Security, or Settings, and jump to the screens for creating an issue or pull request. Requires Windows 11, PowerToys with Command Palette enabled, and GitHub CLI signed in to GitHub.com. Private, organization, and fork repositories are included when your GitHub CLI account has access. Browser access uses the GitHub account signed in to your browser. GH Jump does not create issues or pull requests automatically.

掲載スクリーンショットには公開リポジトリを使い、privateリポジトリ名や個人情報を含めないよう確認します。サポート先、プライバシーに関する説明、年齢区分、価格・公開地域などの必須項目を完成させてから提出します。審査結果と公開状態はPartner Centerで確認します。[Command Palette拡張の提出項目](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/publish-extension-store)

データの取り扱いは[使い方の「データとプライバシー」](使い方.md#データとプライバシー)に記載しています。英語掲載用の説明案は次のとおりです。掲載時はサポート先とプライバシー説明の公開URLが実際に閲覧できることを確認します。

> GH Jump uses GitHub CLI to retrieve your GitHub.com account name and accessible repositories. Repository search runs locally. The extension caches repository IDs, owners, names, private/fork flags, and the cache timestamp as unencrypted JSON in %LOCALAPPDATA%\GHJump\Cache. Cache filenames contain the GitHub account name, and cached data may include private repository names. GH Jump does not extract or store authentication tokens; GitHub CLI manages authentication. The extension has no advertising, analytics, or developer-operated server. Actions open GitHub URLs in your default browser. To remove cached data, exit Command Palette and delete the cache directory. Uninstalling GH Jump may leave this directory behind. GitHub, GitHub CLI, the browser, PowerToys, and Microsoft Store operate under their own settings and policies. Support: https://github.com/apricot-cake/gh-jump/issues. Do not include tokens or private repository information in public reports.

Supplemental info → Additional Testing Informationには、依存するPowerToys・Command Palette・GitHub CLIと、次の審査者向け手順を記載します。GitHubのパスワードやトークンを提出欄へ記載する必要はありません。

```text
GH Jump is an extension for the Windows Command Palette, not a standalone application.
1. Use Windows 11. Install PowerToys and enable Command Palette.
2. Install GitHub CLI: winget install --id GitHub.cli --exact
3. Sign in using your own GitHub.com account:
   gh auth login --hostname github.com --web
   gh auth status --hostname github.com
   Use the default secure credential storage; do not use --insecure-storage.
4. Install GH Jump, then reload extensions or restart Command Palette.
5. Open Command Palette using its configured shortcut, search for GH Jump, and press Enter.
6. Search for a repository accessible to your account using owner/repository, then press Enter.
   Test these routes from the selected repository's action page:
   - Enter with an empty search: repository home page.
   - i, Enter: Issues.
   - a, Enter: Actions.
   - p, Enter: Pull requests.
   - c, Enter, i, Enter: issue creation screen.
   - c, Enter, p, Enter: pull request comparison screen.
7. Confirm that each final action opens the expected URL in the default browser
   and closes Command Palette. A single remaining search result must still wait for Enter.
Do not submit an issue or pull request. The extension only opens GitHub pages.
For private repositories, sign in to the browser with an account that has access.
The optional gh alias is configured in Command Palette settings.
```

## Extension Galleryへの公開

Storeで公開され、インストールできることを確認した後、`microsoft/CmdPal-Extensions`へ登録するPRを送ります。Galleryは配布物を保管せず、StoreまたはWinGetのインストール先へリンクします。

`extensions/apricot-cake/gh-jump/`に`extension.json`とアイコンを置き、`id`は`apricot-cake.gh-jump`、`title`は`GH Jump`、`installSources`は`type: msstore`と実際のStore product IDを指定します。product IDはmanifestのPackage/Identity/Nameとは別の値です。アイコンはPNGまたはJPEG、100KB以下で、PNGの推奨サイズは256×256です。公開先が未確定の間は、仮のproduct IDでPRを送らないでください。[Gallery投稿手順](https://github.com/microsoft/CmdPal-Extensions/blob/main/docs/CONTRIBUTING.md)

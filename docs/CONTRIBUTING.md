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

実際のキー入力、ページ遷移、ブラウザーのURL、パレット終了はwinapp CLIで検証します。ロックを解除したWindowsのデスクトップ、登録済みgh jump、ログイン済みGitHub CLIが必要です。検証中はパレットとブラウザーが前面に出ます。

```powershell
winget install --id Microsoft.WinAppCli --exact --source winget
./scripts/Verify-UI.ps1
```

このスクリプトはwinapp CLI 0.7.1を対象にしています。呼び出しキーの既定値はAlt＋Spaceです。Command Paletteで別のキーを設定している場合は、`-ActivationShortcut 'win+alt+space'`などで指定してください。`gh`検索でgh jumpが先頭候補になることも検証します。

対象は`apricot-cake/gh-jump`です。別のリポジトリを使う場合は`-Repository 'owner/repository'`を指定します。トップ、Issues、Actions、Pull requests、Create → Issue、Create → Pull requestの6経路を確認します。作成画面を開くところまでで、IssueやPRは投稿しません。

一つの経路だけを確認する場合は`-Scenario Top`などを指定します。各経路の実行前に、開いているブラウザーウィンドウのアドレス欄を確認します。遷移先と同じURLが表示されている場合だけ、そのタブを`about:blank`へ移動し、実行前後の変化を確認できるようにします。結果は`artifacts/e2e`のJSONへ保存します。取得したリポジトリ一覧やブラウザーのページ本文、実行前のURLは保存しません。失敗や環境の制約による中断は成功として扱いません。

ブラウザーのURLはChrome、Edge、Firefoxの各ウィンドウで表示中のタブのアドレス欄から読み取ります。前面に来ることは成功条件に含めません。ブラウザーの言語やUI構成によりアドレス欄を取得できない場合は失敗します。段階ごとのページ名、入力の一致、候補数、選択状態、経過時間もJSONに記録します。対話型デスクトップを必要とするため、通常のCIには含めていません。[winappのUI Automation仕様](https://github.com/microsoft/winappCli/blob/main/docs/ui-automation.md)を参照してください。

## 開発用に登録する

ソースコードと[Microsoft Store版](https://apps.microsoft.com/detail/9NN7GSPR8W9R)を公開しています。WinGet、Extension Galleryには未公開です。

Windows 11でPowerToysのCommand PaletteとGitHub CLIを有効にしてください。開発用の登録と配布用MSIXのインストールは異なります。開発用登録はWindowsの開発者モードを有効にして行います。配布用MSIXは信頼できる証明書の署名が必要です。CIが作る未署名パッケージを、そのまま一般利用者へ配布することはできません。

上記の検証スクリプトでビルドとパッケージ作成を終えた後、次の手順で開発用登録します。

```powershell
./scripts/Register-Dev.ps1 -Architecture x64
```

登録スクリプトは登録後にCommand Paletteを再起動します。修正を反映するときも、ビルドとパッケージ作成後にこのスクリプトを実行してください。Command Paletteのエイリアス設定でgh jumpに `gh` を登録すると、以後は `gh` で呼び出せます。

## Microsoft Storeへの提出

配布先はMicrosoftが推奨するMicrosoft Storeです。提出にはPartner Centerの登録、名前の予約、割り当てられたパッケージ識別情報の反映が必要です。パッケージの構造検証とStoreの審査は別に行います。[公式公開ガイド](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/publish-extension)

### 名前とパッケージ識別情報

[Partner Center](https://partner.microsoft.com/)で開発者登録し、Apps and gamesからMSIX製品を作成して`gh jump`の名前を予約します。Product management → Product identityに表示される次の3項目を取得します。値は省略・推測せず、そのまま使用してください。

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

### GitHub Actionsからの提出

Actionsの`Microsoft Store` workflowを`main`から手動実行します。モードは次のとおりです。Storeの審査完了や公開完了をworkflowの成功とはみなしません。

| モード | 操作 |
| --- | --- |
| `verify`（既定） | API認証と提出状態の読み取り |
| `submit` | 検証済みのx64・ARM64 bundleを審査へ提出 |
| `listing-verify` | 公開済み掲載データにローカルの変更を適用できるか、書き込みなしで確認 |
| `listing-submit` | 掲載文・画像を更新して審査へ提出。パッケージは公開済みのものを維持 |

すべてのモードでビルド、テスト、整形・Analyzer、bundle・掲載データの検証を先に実行します。その後、`microsoft-store` Environmentの承認を受けてから認証します。Environmentは`main`だけを許可し、必要なレビュアーを設定し、管理者による保護ルールの回避を無効にしてください。

EnvironmentのVariablesには`MSSTORE_TENANT_ID`、`MSSTORE_CLIENT_ID`、`MSSTORE_SELLER_ID`を設定します。Partner Centerに関連付けたEntraの提出用アプリへ`Manager(Windows)`を付与し、GitHub OIDCのissuer `https://token.actions.githubusercontent.com`、audience `api://AzureADTokenExchange`と、このリポジトリのEnvironmentを表す実際のsubjectを登録します。GitHubのimmutable subjectを有効にしたリポジトリでは、ownerとrepositoryの固定IDを含むsubjectを使用します。[GitHubのOIDC設定](https://docs.github.com/en/actions/reference/security/oidc)、[Store APIの認証要件](https://learn.microsoft.com/en-us/windows/uwp/monetize/create-and-manage-submissions-using-windows-store-services)

パッケージ更新にはMicrosoft公式Store Developer CLI、掲載更新には公式REST APIを使用します。掲載更新はAPIの返却項目を保持し、CLIの内部モデルが扱わない画像の説明なども引き継ぎます。長期有効なclient secretは保存せず、承認済みジョブのOIDCトークンをそのステップ内でのみ使用します。CLIの生出力やAPIの認証情報・署名付きアップロードURLは、公開ログやartifactへ保存しません。[公式CLI](https://learn.microsoft.com/en-us/windows/apps/publish/msstore-dev-cli/commands)

`submit`と`listing-submit`は未完了の提出がある場合、既存の下書きを上書きせず停止します。`submit`では新しいbundleのバージョンを公開済みの全パッケージより大きくしてください。掲載文や画像は公開済み提出から引き継ぎます。

### 掲載文と画像を更新する

[store/listings.json](../store/listings.json)に言語ごとの変更を記述し、画像は`store/images`へ置きます。日本語の掲載情報は[store/listings.ja-jp.json](../store/listings.ja-jp.json)です。このファイルには英語側の製品名も含め、両言語の名称を同じ提出で更新します。Actionsの`listing_file`で更新するファイルを選択します。入力はStore APIのフィールド名を使用します。`description`、`shortDescription`、`features`、`releaseNotes`、`keywords`、`title`、`licenseTerms`、`copyrightAndTrademarkInfo`を変更できます。`shortDescription`は1000文字までです。省略したフィールド・言語・公開済みパッケージはそのまま引き継ぎます。空文字や空配列は、そのフィールドを空にする指定です。

`images`には`fileName`（掲載データファイルからの相対パス）、`description`、`imageType`を指定します。現在はデスクトップの`Screenshot`に対応しています。既存スクリーンショットを置き換え、ロゴなど他の種類の画像は維持します。PNGを使用し、横向きは1366×768以上、縦向きは768×1366以上にしてください。1言語につき10枚まで、1枚50MBまで、説明は200文字までです。パスは`store`内に限定します。画像を変更しない場合は`images`を省略します。[スクリーンショットの要件](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images)

新しい掲載言語もAPIで追加できます。予約済みの製品名を`title`に指定し、空でない`description`と少なくとも1枚の`Screenshot`を含めてください。別の言語の掲載文を自動で複製しません。掲載言語の追加は拡張本体の翻訳とは別の変更です。[公式StoreBrokerの言語追加例](https://github.com/microsoft/StoreBroker/blob/master/Documentation/USAGE.md)、[掲載情報の要件](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/add-and-edit-store-listing-info)

```powershell
./scripts/Test-StoreListing.ps1
```

変更をcommit・pushし、`listing-verify`で公開済み掲載情報との組み合わせを確認します。その後、`listing-submit`を実行してEnvironmentの承認を通します。アプリの表示名などパッケージも同時に更新する場合は、`listing-verify`と`listing-submit`の両方で`include_package`を有効にします。ビルド済みbundleと掲載情報を同じ提出へ送り、bundleのバージョンは公開済みの全パッケージより大きいことを確認します。製品名は事前にPartner Centerで予約してください。画像はZIPにまとめ、APIが発行したアップロード先へ送信します。アップロード失敗時は審査への提出を行いません。

APIで作成した下書きをPartner Centerで編集すると、APIから更新・提出できなくなる場合があります。同じ下書きはAPIだけで管理してください。失敗時は提出状態を確認し、残った下書きを意図せず上書きしないようにします。プライバシーポリシー・サポート先・WebサイトURLは、このAPIの掲載フィールドでは更新できないためPartner CenterのPropertiesで変更します。[Microsoft Store submission API](https://learn.microsoft.com/en-us/windows/uwp/monetize/manage-app-submissions)

### 掲載内容と審査

Partner CenterのPackagesへbundleをアップロードします。パッケージの言語は`en-us`です。English (United States)のDescriptionには、次の説明案を使用できます。

> gh jump integrates with the Windows Command Palette to help you find GitHub repositories and open their pages using your keyboard. Search by repository name, owner, or owner/repository. Open the repository home page, Issues, Pull requests, Actions, Releases, Security, or Settings, and jump to the screens for creating an issue or pull request. Requires Windows 11, PowerToys with Command Palette enabled, and GitHub CLI signed in to GitHub.com. Private, organization, and fork repositories are included when your GitHub CLI account has access. Browser access uses the GitHub account signed in to your browser. gh jump does not create issues or pull requests automatically.

掲載スクリーンショットには公開リポジトリを使い、privateリポジトリ名や個人情報を含めないよう確認します。サポート先、プライバシーに関する説明、年齢区分、価格・公開地域などの必須項目を完成させてから提出します。審査結果と公開状態はPartner Centerで確認します。[Command Palette拡張の提出項目](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/publish-extension-store)

データの取り扱いは[使い方の「データとプライバシー」](使い方.md#データとプライバシー)に記載しています。英語掲載用の説明案は次のとおりです。掲載時はサポート先とプライバシー説明の公開URLが実際に閲覧できることを確認します。

> gh jump uses GitHub CLI to retrieve your GitHub.com account name and accessible repositories. Repository search runs locally. The extension caches repository IDs, owners, names, private/fork flags, and the cache timestamp as unencrypted JSON in %LOCALAPPDATA%\GHJump\Cache. Cache filenames contain the GitHub account name, and cached data may include private repository names. gh jump does not extract or store authentication tokens; GitHub CLI manages authentication. The extension has no advertising, analytics, or developer-operated server. Actions open GitHub URLs in your default browser. To remove cached data, exit Command Palette and delete the cache directory. Uninstalling gh jump may leave this directory behind. GitHub, GitHub CLI, the browser, PowerToys, and Microsoft Store operate under their own settings and policies. Support: https://github.com/apricot-cake/gh-jump/issues. Do not include tokens or private repository information in public reports.

Supplemental info → Additional Testing Informationには、依存するPowerToys・Command Palette・GitHub CLIと、次の審査者向け手順を記載します。GitHubのパスワードやトークンを提出欄へ記載する必要はありません。

```text
gh jump is an extension for the Windows Command Palette, not a standalone application.
1. Use Windows 11. Install PowerToys and enable Command Palette.
2. Install GitHub CLI: winget install --id GitHub.cli --exact
3. Sign in using your own GitHub.com account:
   gh auth login --hostname github.com --web
   gh auth status --hostname github.com
   Use the default secure credential storage; do not use --insecure-storage.
4. Install gh jump, then reload extensions or restart Command Palette.
5. Open Command Palette using its configured shortcut, search for gh jump, and press Enter.
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

`extensions/apricot-cake/gh-jump/`に`extension.json`とアイコンを置き、`id`は`apricot-cake.gh-jump`、`title`は`gh jump`、`installSources`は`type: msstore`と実際のStore product IDを指定します。product IDはmanifestのPackage/Identity/Nameとは別の値です。アイコンはPNGまたはJPEG、100KB以下で、PNGの推奨サイズは256×256です。公開先が未確定の間は、仮のproduct IDでPRを送らないでください。[Gallery投稿手順](https://github.com/microsoft/CmdPal-Extensions/blob/main/docs/CONTRIBUTING.md)

## プロダクトページ

`website`にAstroの静的ページを置きます。Node.jsのバージョンは`.node-version`、依存関係は`website/package-lock.json`で固定します。

```powershell
cd website
npm ci
npm run dev
npm run check
npm run build
```

画像は`website/public/screenshots`、採用済みOcticonsは`website/public/icons`に置きます。変更をmainへpushすると、プロダクトページのワークフローが型検査とビルドを行い、GitHub Pagesへ公開します。アプリ本体のStore提出とは別の処理です。

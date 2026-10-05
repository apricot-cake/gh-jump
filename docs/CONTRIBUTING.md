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

Microsoft公式の拡張方式と標準ページを採用し、独自UIや認証を作らない構成にしています。GitHub APIはCLIへ任せ、拡張内へのトークン持ち込みとSDK依存を減らします。調査日、比較した案、公式資料は[技術スタックの選定](技術スタック.md)に記載しています。

## ビルドと検証

必要な環境は.NET 10 SDK、Windows SDK、Windows 11、PowerToysです。プロジェクト内のSDK指定は `global.json` を参照してください。

```powershell
./scripts/Verify.ps1 -Configuration Release -Architecture x64
```

検証スクリプトでビルド、unit test、整形・Analyzer、MSIXパッケージ検証を実行します。パッケージの出力先は `artifacts/packages` です。GitHub Actionsでも同じスクリプトを実行します。

リポジトリの運用設定は[リポジトリ設定](リポジトリ設定.md)を参照してください。NuGetの取得元は `NuGet.Config` でnuget.orgに固定しています。CIはGitleaksによる秘密情報検査と、PRのDependency Reviewも実行します。NuGetとGitHub Actionsの更新はDependabotが週次で提案します。Command Palette SDKの更新はホストとの互換性を確認して取り込みます。

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

Command Paletteで拡張を再読み込みし、GH Jumpを開いてください。Command Paletteのエイリアス設定でGH Jumpに `gh` を登録すると、以後は `gh` で呼び出せます。

## Extension Galleryへの公開

公開を決めた場合は、まずMSIXのpublisher・identityを確定し、Microsoft StoreまたはWinGetで配布します。Microsoftの推奨経路はStoreです。WinGetでは `windows-commandpalette-extension` タグを付けます。[公式公開ガイド](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/publish-extension)

Galleryは配布物を保管せず、StoreまたはWinGetのインストール先へリンクします。配布先を用意した後、`microsoft/CmdPal-Extensions`へアイコンと `extension.json` を追加するPRを送ります。ソースを非公開にしたままでも、公開インストール先と利用者向けの案内は必要です。[Gallery投稿手順](https://github.com/microsoft/CmdPal-Extensions/blob/main/docs/CONTRIBUTING.md)

## 検証記録（2026-10-04）

Windows 11 / Command Palette 0.11.11762.0で、ビルド・Analyzer・整形、53件の自動テスト、MSIX作成・検証、COM経由の拡張起動・リポジトリ取得・ページ構成を確認しました。実アカウントの8件中5件のprivateリポジトリを取得できました。organization・fork・pagination・認証切れ・API失敗・キャッシュは自動テストで検証しています。実アカウントにはorganization・forkがないため、その実データ確認は未実施です。

公式Toolkitによる500件の検索は、200回の平均で約0.63msでした。

## E2E検証記録（2026-10-05）

Windows 11 / Command Palette 0.11.11762.0 / winapp CLI 0.7.1 / Chromeで、実際のキー入力による6経路を確認しました。対象は`apricot-cake/gh-jump`です。リポジトリ選択後の未入力Enter、`i`、`a`、`p`、`c` → Enter → `i`、`c` → Enter → `p`で、それぞれトップ、Issues、Actions、Pull requests、新規Issue、PR作成画面へ遷移しました。各経路でブラウザーのURLとパレット終了を確認しています。リポ候補が1件でもEnterまで遷移せず、所有者がサブ表示されることも確認しました。

検証スクリプトでは、空の検索欄へのBackspaceが親ページへ戻る操作になるため、入力の消去にDeleteを使います。ブラウザーは背面に開く場合もあるため、前面化ではなくアドレス欄のURLで判定します。結果は`artifacts/e2e/ui-20261005-113648.json`に保存しました。Edge・Firefoxでの実行と、organization・forkの実データ確認は未実施です。

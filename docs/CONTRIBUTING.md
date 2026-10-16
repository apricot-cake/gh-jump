# CONTRIBUTING.md

開発環境の準備、ビルド、検証、開発用登録について説明します。構成は[アーキテクチャ](アーキテクチャ.md)、配布は[ストア提出](ストア提出.md)、認証と操作は[使い方](使い方.md)を参照してください。コマンドはリポジトリのルートで実行します。

## ビルドと検証

必要な環境は.NET 10 SDK、Windows SDK、Windows 11、PowerToysです。プロジェクト内のSDK指定は `global.json` を参照してください。

```powershell
./scripts/Verify.ps1 -Configuration Release -Architecture x64
```

検証スクリプトでビルド、unit test、整形・Analyzer、MSIXパッケージ検証を実行します。パッケージの出力先は `artifacts/packages` です。GitHub Actionsでも同じスクリプトを実行します。

NuGetの取得元は `NuGet.Config` でnuget.orgに固定しています。CIはGitleaksによる秘密情報検査と、PRのDependency Reviewも実行します。NuGetとGitHub Actionsの更新はDependabotが週次で提案します。コマンドパレット SDKの更新はホストとの互換性を確認して取り込みます。

登録済み拡張の実データ取得とページ構成は、次のコマンドでも確認できます。

```powershell
./scripts/Verify-Activation.ps1 -LoadRepositories
```

### コマンドパレット上のE2E

実際のキー入力、ページ遷移、ブラウザーのURL、パレット終了はwinapp CLIで検証します。ロックを解除したWindowsのデスクトップ、登録済みgh jump、ログイン済みGitHub CLIが必要です。検証中はパレットとブラウザーが前面に出ます。

```powershell
winget install --id Microsoft.WinAppCli --exact --source winget
./scripts/Verify-UI.ps1
```

このスクリプトはwinapp CLI 0.7.1を対象にしています。呼び出しキーの既定値はAlt＋Spaceです。コマンドパレットで別のキーを設定している場合は、`-ActivationShortcut 'win+alt+space'`などで指定してください。`gh`検索でgh jumpが先頭候補になることも検証します。

対象は`apricot-cake/gh-jump`です。別のリポジトリを使う場合は`-Repository 'owner/repository'`を指定します。トップ、Issues、Actions、Pull requests、Create → Issue、Create → Pull requestの6経路を確認します。作成画面を開くところまでで、IssueやPRは投稿しません。

一つの経路だけを確認する場合は`-Scenario Top`などを指定します。各経路の実行前に、開いているブラウザーウィンドウのアドレス欄を確認します。遷移先と同じURLが表示されている場合だけ、そのタブを`about:blank`へ移動し、実行前後の変化を確認できるようにします。結果は`artifacts/e2e`のJSONへ保存します。取得したリポジトリ一覧やブラウザーのページ本文、実行前のURLは保存しません。失敗や環境の制約による中断は成功として扱いません。

ブラウザーのURLはChrome、Edge、Firefoxの各ウィンドウで表示中のタブのアドレス欄から読み取ります。前面に来ることは成功条件に含めません。ブラウザーの言語やUI構成によりアドレス欄を取得できない場合は失敗します。段階ごとのページ名、入力の一致、候補数、選択状態、経過時間もJSONに記録します。対話型デスクトップを必要とするため、通常のCIには含めていません。[winappのUI Automation仕様](https://github.com/microsoft/winappCli/blob/main/docs/ui-automation.md)を参照してください。

## 開発用に登録する

ソースコードと[Microsoft Store版](https://apps.microsoft.com/detail/9NN7GSPR8W9R)を公開しています。WinGet、Extension Galleryには未公開です。

Windows 11でPowerToysのコマンドパレットとGitHub CLIを有効にしてください。開発用の登録と配布用MSIXのインストールは異なります。開発用登録はWindowsの開発者モードを有効にして行います。配布用MSIXは信頼できる証明書の署名が必要です。CIが作る未署名パッケージを、そのまま一般利用者へ配布することはできません。

上記の検証スクリプトでビルドとパッケージ作成を終えた後、次の手順で開発用登録します。

```powershell
./scripts/Register-Dev.ps1 -Architecture x64
```

登録スクリプトは登録後にコマンドパレットを再起動します。修正を反映するときも、ビルドとパッケージ作成後にこのスクリプトを実行してください。コマンドパレットのエイリアス設定でgh jumpに `gh` を登録すると、以後は `gh` で呼び出せます。

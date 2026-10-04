# 第三者ソフトウェアのライセンス

GH Jump の独自コードには、パッケージのルートにある `LICENSE`（MIT）を適用します。
以下の第三者ソフトウェアには、それぞれのライセンスを適用します。Windows SDK の配布コードには Microsoft の SDK ライセンス条項を適用します。

| コンポーネント | 配布対象 | ライセンス文書 |
| --- | --- | --- |
| Microsoft.CommandPalette.Extensions 0.11.260520004 | Extension SDK と Toolkit の DLL | [CommandPalette-SDK-MIT.txt](CommandPalette-SDK-MIT.txt) |
| Microsoft.Windows.CsWinRT 2.2.0 | WinRT.Runtime.dll | [CsWinRT-MIT.txt](CsWinRT-MIT.txt) |
| Shmuelie.WinRTServer 2.1.1 | Shmuelie.WinRTServer.dll | [WinRTServer-MIT.txt](WinRTServer-MIT.txt) |
| ToolGood.Words.Pinyin 3.1.0.3 | ToolGood.Words.Pinyin.dll | [ToolGood-Words-Pinyin-MIT.txt](ToolGood-Words-Pinyin-MIT.txt) |
| Microsoft.Windows.SDK.NET.Ref 10.0.26100.57 | Microsoft.Windows.SDK.NET.dll | [Windows-SDK.rtf](Windows-SDK.rtf) |
| .NET Runtime 10.0.12 | 自己完結型アプリに含まれるマネージド／ネイティブランタイム | [NET-Runtime-MIT.txt](NET-Runtime-MIT.txt)、[NET-Runtime-Third-Party-Notices.txt](NET-Runtime-Third-Party-Notices.txt) |
| Octicons | SVG とそこから生成した PNG | [Octicons-MIT.txt](Octicons-MIT.txt) |

パッケージメタデータの著作権表記: Shmuelie.WinRTServer は Copyright (c) 2025 Shmueli Englard、ToolGood.Words.Pinyin は Copyright 2017-2025 ToolGood。それぞれの LICENSE 原文の著作権表記も変更せず保持しています。

## 原文の取得元

- Command Palette: NuGet パッケージの MIT 表記と [PowerToys の LICENSE](https://github.com/microsoft/PowerToys/blob/main/LICENSE)。
- CsWinRT、WinRTServer、ToolGood.Words.Pinyin、.NET Runtime: 各バージョンの NuGet パッケージに含まれる `LICENSE` と `THIRD-PARTY-NOTICES.TXT`。ランタイムの第三者通知は省略せず同梱しています。
- Windows SDK: NuGet パッケージの `licenseUrl` が指定する [Microsoft のライセンス原文](https://aka.ms/WinSDKLicenseURL)。RTF の原文を変更せず同梱しています。
- Octicons: [公式リポジトリのコミット 923a31b34542702800cb90a0fd390e2e60dd92ac](https://github.com/primer/octicons/tree/923a31b34542702800cb90a0fd390e2e60dd92ac)。元の文書は `Assets/Octicons/LICENSE` にも含まれています。

依存パッケージや .NET SDK／ランタイムのバージョンを更新した場合は、配布対象と原文を再確認してください。テストランナーとビルド専用の CsWinRT ツールはアプリに含まれません。GitHub CLI はユーザーが別途インストールする前提で、GH Jump のパッケージには含まれません。

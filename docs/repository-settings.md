# リポジトリの運用設定

GitHubの設定はワークフローとは別に管理する。既存リポジトリの運用に合わせ、GH Jumpでは以下を有効にしている。

| 項目 | 設定 |
| --- | --- |
| マージ方式 | Squashのみ許可 |
| マージ後のブランチ | 自動削除 |
| Auto-merge | 利用可能。各PRでの有効化は別途行う |
| main ruleset | デフォルトブランチの削除・force pushを禁止 |
| Secret scanning / push protection | 有効 |
| Dependabot alerts / security updates | 有効 |
| CodeQL | Default setup、C#とGitHub Actions、標準クエリ |
| Actionsの既定権限 | Read。PRレビューの自動承認は無効 |

PR・レビュー承認・CI成功の必須化は行っていない。設定を確認するときはGitHubの現在の状態を参照する。

CIはActionsを完全SHAで固定する。DependabotはActionsとNuGetを週次で更新し、依存更新には「依存更新」ラベルを付ける。NuGetのminor・patch更新はまとめ、Command Palette SDKはホストとの互換性確認のため個別に扱う。

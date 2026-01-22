# CLAUDE.md

このファイルはClaude Codeがこのリポジトリで作業する際のガイダンスを提供します。

## プロジェクト概要

Tapbackは、モバイル端末からClaude Code/Codexのターミナルを監視・操作するmacOSメニューバーアプリです。tmuxセッションの出力をWebSocket経由でリアルタイム配信し、localhostで動作するWebアプリへのリバースプロキシ機能も提供します。

## ビルドとテスト

```bash
# ビルド
swift build

# 実行
swift run TapbackApp

# フォーマット
swiftformat Sources
```

## アーキテクチャ

### ディレクトリ構造

```text
Sources/TapbackApp/
├── TapbackApp.swift          # エントリーポイント、メニューバーアプリ定義
├── Models/
│   ├── TmuxHelper.swift      # tmuxコマンド実行ヘルパー
│   ├── Session.swift         # セッションモデル（レガシー）
│   └── SessionManager.swift  # セッション管理（レガシー）
├── Server/
│   ├── ServerManager.swift   # Vaporサーバー、WebSocket、リバースプロキシ
│   └── HTMLTemplates.swift   # モバイルUI用HTML/CSS/JS
└── Views/
    ├── ContentView.swift     # メインウィンドウUI
    └── MenuBarView.swift     # メニューバーUI（未使用）
```

### 主要コンポーネント

- **ServerManager**: Vaporベースのサーバー。ターミナルUI用サーバー（ポート9876）とプロキシサーバーを管理
- **TmuxHelper**: tmuxコマンド（capture-pane, send-keys, list-sessions等）のasync/awaitラッパー
- **HTMLTemplates**: モバイル向けのレスポンシブWebUI。セッションタブ、クイックボタン、WebSocket接続を含む

### 通信フロー

1. モバイル → `/api/sessions` でtmuxセッション一覧取得
2. モバイル → `/ws` WebSocket接続
3. サーバー → 全tmuxセッションの出力を1秒ごとにブロードキャスト
4. モバイル → WebSocketでコマンド送信 → `TmuxHelper.sendKeys`でtmuxに転送

## コーディング規約

- Swift 5.9以上、macOS 13+
- 非同期処理は`async/await`と`withCheckedContinuation`を使用
- UIはSwiftUI、サーバーはVapor
- フォーマットは`swiftformat`で統一

## 依存関係

- **Vapor 4.89+**: HTTPサーバー、WebSocket
- **SwiftTerm**: 埋め込みターミナルビュー（Mac側UI用）

## 注意点

- tmuxコマンドは明示的に`session:0.0`を指定（複数ウィンドウ/ペーン対応のため）
- PATH設定で`/opt/homebrew/bin`と`/usr/local/bin`を追加（tmux検出用）
- プロキシはlocalhost参照を自動的にMacのIPに書き換え

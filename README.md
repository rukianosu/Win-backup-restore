# Win-backup-restore

外付けHDDに保存された旧PCのユーザーデータを、新しいWindows環境へ安全に復元する自動ツール

## 機能

- **外付けHDDの自動検出**: 接続されたドライブを自動でスキャンし、Usersフォルダを検出
- **GUIでユーザー選択**: WinFormsベースのGUIで復元対象ユーザーを複数選択可能
- **標準フォルダ復元**: Desktop, Documents, Pictures, Videos, Music, Downloads
- **AppData復元**: 辞書（Dictionaries）、テーマ（Themes）
- **クラウドドライブ復元**: OneDrive, Dropbox, iCloud, GoogleDrive（存在する場合）
- **ブラウザブックマーク復元**: Microsoft Edge, Google Chrome
- **レジストリ復元**: IME設定、タブレット設定など安全なキーのみ

## ファイル構成

```
Win-backup-restore/
├── Main-Restore.ps1              # メインスクリプト（エントリーポイント）
├── Modules/
│   ├── Scan-Backup.ps1           # 外付けHDD検出・ユーザースキャン
│   ├── Restore-GUI.ps1           # WinForms GUI
│   ├── Copy-UserData.ps1         # robocopyによるフォルダコピー
│   ├── Restore-BrowserBookmarks.ps1  # ブックマーク復元
│   └── Restore-Registry.ps1      # レジストリ復元
└── README.md
```

## 動作要件

- Windows 10/11
- PowerShell 5.1以上
- 管理者権限（レジストリ復元に必要）

## 使い方

### 基本的な使い方（GUI）

1. 外付けHDDをPCに接続
2. PowerShellを**管理者として実行**
3. スクリプトを実行:

```powershell
.\Main-Restore.ps1
```

4. GUIで復元対象ユーザーを選択
5. 「復元開始」ボタンをクリック

### サイレントモード（全自動）

```powershell
.\Main-Restore.ps1 -Silent
```

GUIを表示せず、検出されたすべてのユーザーを自動復元します。

### カスタムログパス

```powershell
.\Main-Restore.ps1 -LogPath "D:\Logs\Restore.log"
```

## 復元オプション

GUIで以下のオプションを個別に選択できます:

| オプション | 説明 |
|-----------|------|
| Desktop | デスクトップフォルダ |
| Documents | ドキュメントフォルダ |
| Pictures | ピクチャフォルダ |
| Videos | ビデオフォルダ |
| Music | ミュージックフォルダ |
| Downloads | ダウンロードフォルダ |
| AppData | 辞書・テーマ設定 |
| ブラウザブックマーク | Edge/Chromeのお気に入り |
| レジストリ設定 | IME・キーボード設定 |
| クラウドドライブ | OneDrive/Dropbox等 |

## レジストリ復元について

### 復元対象（安全なキー）

- IME設定（`Software\Microsoft\InputMethod`）
- タブレット設定（`Software\Microsoft\TabletTip`）
- ユーザー辞書設定（`Software\Microsoft\IME`）
- キーボードレイアウト（`Keyboard Layout`）
- コンソール設定（`Console`）
- 環境変数（`Environment`）

### 復元禁止（危険なキー）

以下は安全のため自動的にスキップされます:

- ドライバ関連
- サービス関連
- セキュリティポリシー
- ネットワーク設定
- スタートアップ設定
- 認証・暗号化関連

## ログ

実行ログは以下に出力されます:

```
C:\AutoSetup\Logs\Restore.log
```

ログには以下が記録されます:
- コピー成功/失敗
- スキップ理由
- エラー詳細
- 処理時間

## 注意事項

1. **バックアップ推奨**: 復元前に現在のデータをバックアップしてください
2. **管理者権限**: レジストリ復元には管理者権限が必要です
3. **ブラウザを閉じる**: ブックマーク復元前にEdge/Chromeを閉じてください
4. **既存ファイル**: 既存ファイルより新しいファイルのみ上書きされます（`/XO`オプション）

## トラブルシューティング

### ドライブが検出されない

- 外付けHDDが正しく接続されているか確認
- エクスプローラーでドライブが表示されるか確認
- ドライブレターが割り当てられているか確認

### レジストリ復元がスキップされる

- PowerShellを「管理者として実行」しているか確認
- NTUSER.DATファイルが存在するか確認

### robocopyエラー

- 宛先フォルダの書き込み権限を確認
- ウイルス対策ソフトが干渉していないか確認

## ライセンス

MIT License

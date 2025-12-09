# Win-backup-restore

PCのユーザーデータをバックアップ・復元する自動ツール（GUI付き）

## 概要

**2つのツールで構成:**

| ツール | 説明 |
|--------|------|
| `Main-Backup.ps1` | 今のPCから外付けHDDにバックアップ |
| `Main-Restore.ps1` | 外付けHDDから新しいPCに復元 |

## ファイル構成

```
Win-backup-restore/
├── Main-Backup.ps1               # バックアップ用メインスクリプト
├── Main-Restore.ps1              # 復元用メインスクリプト
├── Modules/
│   ├── Backup-GUI.ps1            # バックアップ用GUI
│   ├── Backup-UserData.ps1       # バックアップ処理
│   ├── Backup-Registry.ps1       # レジストリエクスポート
│   ├── Scan-Backup.ps1           # 外付けHDD検出
│   ├── Restore-GUI.ps1           # 復元用GUI
│   ├── Copy-UserData.ps1         # 復元処理
│   ├── Restore-BrowserBookmarks.ps1  # ブックマーク復元
│   └── Restore-Registry.ps1      # レジストリ復元
└── README.md
```

## 動作要件

- Windows 10/11
- PowerShell 5.1以上
- 管理者権限推奨（レジストリ操作に必要）

---

## 使い方

### Step 1: バックアップ（旧PC）

1. 外付けHDDを接続
2. PowerShellを**管理者として実行**
3. 実行:

```powershell
.\Main-Backup.ps1
```

4. GUIでバックアップ先ドライブを選択
5. 「バックアップ開始」をクリック

### Step 2: 復元（新PC）

1. バックアップした外付けHDDを接続
2. PowerShellを**管理者として実行**
3. 実行:

```powershell
.\Main-Restore.ps1
```

4. GUIで復元するユーザーを選択
5. 「復元開始」をクリック

---

## バックアップ・復元対象

| 対象 | 説明 |
|------|------|
| Desktop | デスクトップフォルダ |
| Documents | ドキュメントフォルダ |
| Pictures | ピクチャフォルダ |
| Videos | ビデオフォルダ |
| Music | ミュージックフォルダ |
| Downloads | ダウンロードフォルダ |
| AppData | 辞書・テーマ設定 |
| ブックマーク | Edge/Chromeのお気に入り |
| レジストリ | IME・キーボード設定 |
| クラウドドライブ | OneDrive/Dropbox等 |

---

## コマンドオプション

### バックアップ

```powershell
# GUI表示（通常）
.\Main-Backup.ps1

# サイレントモード（自動実行）
.\Main-Backup.ps1 -Silent

# カスタムログパス
.\Main-Backup.ps1 -LogPath "D:\Logs\Backup.log"
```

### 復元

```powershell
# GUI表示（通常）
.\Main-Restore.ps1

# サイレントモード（全ユーザー復元）
.\Main-Restore.ps1 -Silent

# カスタムログパス
.\Main-Restore.ps1 -LogPath "D:\Logs\Restore.log"
```

---

## レジストリについて

### バックアップ・復元対象（安全なキー）

- IME設定
- タブレット設定
- ユーザー辞書設定
- キーボードレイアウト
- コンソール設定
- 環境変数
- エクスプローラー設定

### 復元禁止（危険なキー）

以下は安全のため自動スキップ:
- ドライバ / サービス
- セキュリティポリシー
- ネットワーク設定
- スタートアップ設定

---

## ログ

| 種類 | パス |
|------|------|
| バックアップ | `C:\AutoSetup\Logs\Backup.log` |
| 復元 | `C:\AutoSetup\Logs\Restore.log` |

---

## 注意事項

1. **管理者権限**: レジストリ操作には管理者権限が必要
2. **ブラウザを閉じる**: ブックマーク復元前にEdge/Chromeを終了
3. **十分な空き容量**: バックアップ先に十分な空き容量を確保

---

## トラブルシューティング

### ドライブが検出されない

- 外付けHDDが正しく接続されているか確認
- エクスプローラーでドライブが表示されるか確認

### レジストリ操作が失敗

- PowerShellを「管理者として実行」しているか確認

### robocopyエラー

- 書き込み権限を確認
- ウイルス対策ソフトの干渉を確認

---

## ライセンス

MIT License

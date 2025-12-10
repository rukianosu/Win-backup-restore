<#
.SYNOPSIS
    WinForms GUIでバックアップユーザーを選択するモジュール

.DESCRIPTION
    - 検出されたユーザーをリスト表示
    - 複数選択可能なチェックボックスリスト
    - 復元オプションの選択
    - OKボタンで選択を確定

.NOTES
    PowerShell 5.1 互換
    WinForms使用
#>

# WinFormsアセンブリを読み込み
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#===============================================================================
# 関数: Show-UserSelectionDialog
# 説明: ユーザー選択GUIを表示し、選択されたユーザーを返す
#===============================================================================
function Show-UserSelectionDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Array]$BackupUsers
    )

    # 戻り値用のハッシュテーブル
    $script:DialogResult = @{
        SelectedUsers = @()
        Options = @{
            RestoreDesktop    = $true
            RestoreDocuments  = $true
            RestorePictures   = $true
            RestoreVideos     = $true
            RestoreMusic      = $true
            RestoreDownloads  = $true
            RestoreAppData    = $true
            RestoreBookmarks  = $true
            RestoreRegistry   = $true
            RestoreCloudDrive = $true
            RestoreWiFi       = $true
        }
        Confirmed = $false
    }

    #---------------------------------------------------------------------------
    # メインフォーム作成
    #---------------------------------------------------------------------------
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "ユーザーデータ復元ツール"
    $form.Size = New-Object System.Drawing.Size(650, 580)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9)

    #---------------------------------------------------------------------------
    # タイトルラベル
    #---------------------------------------------------------------------------
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(20, 15)
    $titleLabel.Size = New-Object System.Drawing.Size(600, 25)
    $titleLabel.Text = "復元するユーザーを選択してください（複数選択可）"
    $titleLabel.Font = New-Object System.Drawing.Font("Yu Gothic UI", 11, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($titleLabel)

    #---------------------------------------------------------------------------
    # ユーザーリスト（CheckedListBox）
    #---------------------------------------------------------------------------
    $userListBox = New-Object System.Windows.Forms.CheckedListBox
    $userListBox.Location = New-Object System.Drawing.Point(20, 50)
    $userListBox.Size = New-Object System.Drawing.Size(590, 150)
    $userListBox.CheckOnClick = $true
    $userListBox.Font = New-Object System.Drawing.Font("Consolas", 10)

    # ユーザーをリストに追加
    foreach ($user in $BackupUsers) {
        $displayText = "$($user.UserName) - [$($user.DriveLetter)] $($user.UsersPath)"
        $userListBox.Items.Add($displayText) | Out-Null
    }

    $form.Controls.Add($userListBox)

    #---------------------------------------------------------------------------
    # 復元オプショングループ
    #---------------------------------------------------------------------------
    $optionGroup = New-Object System.Windows.Forms.GroupBox
    $optionGroup.Location = New-Object System.Drawing.Point(20, 210)
    $optionGroup.Size = New-Object System.Drawing.Size(590, 250)
    $optionGroup.Text = "復元オプション"
    $form.Controls.Add($optionGroup)

    # チェックボックス配列
    $checkboxes = @()
    $checkboxData = @(
        @{ Name = "RestoreDesktop";    Text = "Desktop（デスクトップ）";        Y = 25 },
        @{ Name = "RestoreDocuments";  Text = "Documents（ドキュメント）";       Y = 50 },
        @{ Name = "RestorePictures";   Text = "Pictures（ピクチャ）";           Y = 75 },
        @{ Name = "RestoreVideos";     Text = "Videos（ビデオ）";               Y = 100 },
        @{ Name = "RestoreMusic";      Text = "Music（ミュージック）";          Y = 125 },
        @{ Name = "RestoreDownloads";  Text = "Downloads（ダウンロード）";       Y = 150 }
    )

    $checkboxData2 = @(
        @{ Name = "RestoreAppData";    Text = "AppData（辞書・テーマ）";         Y = 25 },
        @{ Name = "RestoreBookmarks";  Text = "ブラウザブックマーク（Edge/Chrome）"; Y = 50 },
        @{ Name = "RestoreRegistry";   Text = "レジストリ設定（IME等）";         Y = 75 },
        @{ Name = "RestoreCloudDrive"; Text = "クラウドドライブ（OneDrive等）";   Y = 100 },
        @{ Name = "RestoreWiFi";       Text = "WiFi設定";                      Y = 125 }
    )

    # 左列のチェックボックス
    foreach ($data in $checkboxData) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Location = New-Object System.Drawing.Point(20, $data.Y)
        $cb.Size = New-Object System.Drawing.Size(250, 22)
        $cb.Text = $data.Text
        $cb.Name = $data.Name
        $cb.Checked = $true
        $optionGroup.Controls.Add($cb)
        $checkboxes += $cb
    }

    # 右列のチェックボックス
    foreach ($data in $checkboxData2) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Location = New-Object System.Drawing.Point(300, $data.Y)
        $cb.Size = New-Object System.Drawing.Size(270, 22)
        $cb.Text = $data.Text
        $cb.Name = $data.Name
        $cb.Checked = $true
        $optionGroup.Controls.Add($cb)
        $checkboxes += $cb
    }

    #---------------------------------------------------------------------------
    # 全選択/全解除ボタン
    #---------------------------------------------------------------------------
    $selectAllBtn = New-Object System.Windows.Forms.Button
    $selectAllBtn.Location = New-Object System.Drawing.Point(20, 185)
    $selectAllBtn.Size = New-Object System.Drawing.Size(100, 25)
    $selectAllBtn.Text = "全選択"
    $selectAllBtn.Add_Click({
        for ($i = 0; $i -lt $userListBox.Items.Count; $i++) {
            $userListBox.SetItemChecked($i, $true)
        }
    })
    $optionGroup.Controls.Add($selectAllBtn)

    $deselectAllBtn = New-Object System.Windows.Forms.Button
    $deselectAllBtn.Location = New-Object System.Drawing.Point(130, 185)
    $deselectAllBtn.Size = New-Object System.Drawing.Size(100, 25)
    $deselectAllBtn.Text = "全解除"
    $deselectAllBtn.Add_Click({
        for ($i = 0; $i -lt $userListBox.Items.Count; $i++) {
            $userListBox.SetItemChecked($i, $false)
        }
    })
    $optionGroup.Controls.Add($deselectAllBtn)

    # オプション全選択/全解除
    $optSelectAllBtn = New-Object System.Windows.Forms.Button
    $optSelectAllBtn.Location = New-Object System.Drawing.Point(350, 185)
    $optSelectAllBtn.Size = New-Object System.Drawing.Size(110, 25)
    $optSelectAllBtn.Text = "オプション全選択"
    $optSelectAllBtn.Add_Click({
        foreach ($cb in $checkboxes) {
            $cb.Checked = $true
        }
    })
    $optionGroup.Controls.Add($optSelectAllBtn)

    $optDeselectAllBtn = New-Object System.Windows.Forms.Button
    $optDeselectAllBtn.Location = New-Object System.Drawing.Point(470, 185)
    $optDeselectAllBtn.Size = New-Object System.Drawing.Size(110, 25)
    $optDeselectAllBtn.Text = "オプション全解除"
    $optDeselectAllBtn.Add_Click({
        foreach ($cb in $checkboxes) {
            $cb.Checked = $false
        }
    })
    $optionGroup.Controls.Add($optDeselectAllBtn)

    #---------------------------------------------------------------------------
    # OK / キャンセルボタン
    #---------------------------------------------------------------------------
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(400, 475)
    $okButton.Size = New-Object System.Drawing.Size(100, 35)
    $okButton.Text = "復元開始"
    $okButton.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10, [System.Drawing.FontStyle]::Bold)
    $okButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $okButton.ForeColor = [System.Drawing.Color]::White
    $okButton.FlatStyle = "Flat"
    $okButton.Add_Click({
        # 選択されたユーザーを取得
        $selectedIndices = $userListBox.CheckedIndices
        if ($selectedIndices.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "復元するユーザーを1つ以上選択してください",
                "選択エラー",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        # 選択されたユーザー情報を格納
        foreach ($index in $selectedIndices) {
            $script:DialogResult.SelectedUsers += $BackupUsers[$index]
        }

        # オプションを格納
        foreach ($cb in $checkboxes) {
            $script:DialogResult.Options[$cb.Name] = $cb.Checked
        }

        $script:DialogResult.Confirmed = $true
        $form.Close()
    })
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(510, 475)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 35)
    $cancelButton.Text = "キャンセル"
    $cancelButton.Add_Click({
        $script:DialogResult.Confirmed = $false
        $form.Close()
    })
    $form.Controls.Add($cancelButton)

    #---------------------------------------------------------------------------
    # フォーム表示
    #---------------------------------------------------------------------------
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()

    return $script:DialogResult
}

#===============================================================================
# 関数: Show-ProgressDialog
# 説明: 復元進捗を表示するダイアログ
#===============================================================================
function Show-ProgressDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $progressForm = New-Object System.Windows.Forms.Form
    $progressForm.Text = $Title
    $progressForm.Size = New-Object System.Drawing.Size(450, 150)
    $progressForm.StartPosition = "CenterScreen"
    $progressForm.FormBorderStyle = "FixedDialog"
    $progressForm.ControlBox = $false
    $progressForm.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(400, 30)
    $label.Text = $Message
    $label.Font = New-Object System.Drawing.Font("Yu Gothic UI", 10)
    $progressForm.Controls.Add($label)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(20, 60)
    $progressBar.Size = New-Object System.Drawing.Size(390, 25)
    $progressBar.Style = "Marquee"
    $progressBar.MarqueeAnimationSpeed = 30
    $progressForm.Controls.Add($progressBar)

    return $progressForm
}

#===============================================================================
# 関数: Show-CompletionDialog
# 説明: 復元完了ダイアログを表示
#===============================================================================
function Show-CompletionDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$SuccessCount,

        [Parameter(Mandatory = $true)]
        [int]$SkipCount,

        [Parameter(Mandatory = $true)]
        [int]$ErrorCount,

        [Parameter(Mandatory = $false)]
        [string]$LogPath = ""
    )

    $message = @"
復元処理が完了しました。

成功: $SuccessCount 項目
スキップ: $SkipCount 項目
エラー: $ErrorCount 項目
"@

    if ($LogPath -and (Test-Path $LogPath)) {
        $message += "`n`nログファイル: $LogPath"
    }

    $icon = if ($ErrorCount -gt 0) {
        [System.Windows.Forms.MessageBoxIcon]::Warning
    } else {
        [System.Windows.Forms.MessageBoxIcon]::Information
    }

    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "復元完了",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

#===============================================================================
# 関数: Show-ErrorDialog
# 説明: エラーダイアログを表示
#===============================================================================
function Show-ErrorDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Title = "エラー"
    )

    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

#===============================================================================
# 関数: Show-ConfirmDialog
# 説明: 確認ダイアログを表示
#===============================================================================
function Show-ConfirmDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Title = "確認"
    )

    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

<#
.SYNOPSIS
    WinForms GUIでバックアップ先と対象を選択するモジュール

.DESCRIPTION
    - 外付けドライブをリスト表示
    - バックアップ対象フォルダを選択
    - バックアップ先フォルダ名を指定

.NOTES
    PowerShell 5.1 互換
    WinForms使用
#>

# WinFormsアセンブリを読み込み
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#===============================================================================
# 関数: Get-AvailableDrives
# 説明: バックアップ先として使用可能なドライブを取得
#===============================================================================
function Get-AvailableDrives {
    [CmdletBinding()]
    param()

    try {
        $drives = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=2 OR DriveType=3" |
            Where-Object {
                $_.DeviceID -ne 'C:' -and
                (Test-Path -Path $_.DeviceID -ErrorAction SilentlyContinue)
            } |
            Select-Object -Property @{
                Name = 'DriveLetter'
                Expression = { $_.DeviceID }
            }, @{
                Name = 'VolumeName'
                Expression = { if ($_.VolumeName) { $_.VolumeName } else { '(名前なし)' } }
            }, @{
                Name = 'DriveType'
                Expression = {
                    switch ($_.DriveType) {
                        2 { 'リムーバブル' }
                        3 { '固定ディスク' }
                        default { '不明' }
                    }
                }
            }, @{
                Name = 'SizeGB'
                Expression = { [math]::Round($_.Size / 1GB, 2) }
            }, @{
                Name = 'FreeSpaceGB'
                Expression = { [math]::Round($_.FreeSpace / 1GB, 2) }
            }

        return $drives
    }
    catch {
        return @()
    }
}

#===============================================================================
# 関数: Show-BackupDialog
# 説明: バックアップ設定GUIを表示
#===============================================================================
function Show-BackupDialog {
    [CmdletBinding()]
    param()

    # 戻り値用のハッシュテーブル
    $script:BackupDialogResult = @{
        TargetDrive = $null
        BackupFolderName = "Backup_$(Get-Date -Format 'yyyyMMdd')"
        Options = @{
            BackupDesktop     = $true
            BackupDocuments   = $true
            BackupPictures    = $true
            BackupVideos      = $true
            BackupMusic       = $true
            BackupDownloads   = $true
            BackupAppData     = $true
            BackupBookmarks   = $true
            BackupRegistry    = $true
            BackupCloudDrive  = $true
            CloseBrowsers     = $true   # ブラウザ自動終了（推奨）
        }
        Confirmed = $false
    }

    #---------------------------------------------------------------------------
    # メインフォーム作成
    #---------------------------------------------------------------------------
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "ユーザーデータ バックアップツール"
    $form.Size = New-Object System.Drawing.Size(600, 640)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9)

    #---------------------------------------------------------------------------
    # タイトルラベル
    #---------------------------------------------------------------------------
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(20, 15)
    $titleLabel.Size = New-Object System.Drawing.Size(550, 25)
    $titleLabel.Text = "バックアップ先ドライブを選択してください"
    $titleLabel.Font = New-Object System.Drawing.Font("Yu Gothic UI", 11, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($titleLabel)

    #---------------------------------------------------------------------------
    # ドライブリスト（ListBox）
    #---------------------------------------------------------------------------
    $driveListBox = New-Object System.Windows.Forms.ListBox
    $driveListBox.Location = New-Object System.Drawing.Point(20, 50)
    $driveListBox.Size = New-Object System.Drawing.Size(540, 100)
    $driveListBox.Font = New-Object System.Drawing.Font("Consolas", 10)

    # ドライブを取得してリストに追加
    $drives = Get-AvailableDrives
    $script:DriveList = $drives

    if ($drives -and $drives.Count -gt 0) {
        foreach ($drive in $drives) {
            $displayText = "$($drive.DriveLetter) - $($drive.VolumeName) ($($drive.DriveType)) [空き: $($drive.FreeSpaceGB)GB / $($drive.SizeGB)GB]"
            $driveListBox.Items.Add($displayText) | Out-Null
        }
        $driveListBox.SelectedIndex = 0
    }
    else {
        $driveListBox.Items.Add("外付けドライブが見つかりません") | Out-Null
        $driveListBox.Enabled = $false
    }

    $form.Controls.Add($driveListBox)

    #---------------------------------------------------------------------------
    # バックアップフォルダ名
    #---------------------------------------------------------------------------
    $folderLabel = New-Object System.Windows.Forms.Label
    $folderLabel.Location = New-Object System.Drawing.Point(20, 160)
    $folderLabel.Size = New-Object System.Drawing.Size(200, 20)
    $folderLabel.Text = "バックアップフォルダ名:"
    $form.Controls.Add($folderLabel)

    $folderTextBox = New-Object System.Windows.Forms.TextBox
    $folderTextBox.Location = New-Object System.Drawing.Point(20, 185)
    $folderTextBox.Size = New-Object System.Drawing.Size(300, 25)
    $folderTextBox.Text = "Backup_$env:COMPUTERNAME`_$(Get-Date -Format 'yyyyMMdd')"
    $folderTextBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $form.Controls.Add($folderTextBox)

    # パスプレビュー
    $pathPreviewLabel = New-Object System.Windows.Forms.Label
    $pathPreviewLabel.Location = New-Object System.Drawing.Point(20, 215)
    $pathPreviewLabel.Size = New-Object System.Drawing.Size(540, 20)
    $pathPreviewLabel.ForeColor = [System.Drawing.Color]::Gray
    $pathPreviewLabel.Text = ""
    $form.Controls.Add($pathPreviewLabel)

    # パスプレビュー更新関数
    $updatePreview = {
        if ($driveListBox.SelectedIndex -ge 0 -and $script:DriveList.Count -gt 0) {
            $selectedDrive = $script:DriveList[$driveListBox.SelectedIndex]
            $pathPreviewLabel.Text = "保存先: $($selectedDrive.DriveLetter)\$($folderTextBox.Text)\Users\$env:USERNAME"
        }
    }

    $driveListBox.Add_SelectedIndexChanged($updatePreview)
    $folderTextBox.Add_TextChanged($updatePreview)
    & $updatePreview

    #---------------------------------------------------------------------------
    # バックアップ対象オプショングループ
    #---------------------------------------------------------------------------
    $optionGroup = New-Object System.Windows.Forms.GroupBox
    $optionGroup.Location = New-Object System.Drawing.Point(20, 245)
    $optionGroup.Size = New-Object System.Drawing.Size(540, 270)
    $optionGroup.Text = "バックアップ対象"
    $form.Controls.Add($optionGroup)

    # チェックボックス配列
    $checkboxes = @()
    $checkboxData = @(
        @{ Name = "BackupDesktop";    Text = "Desktop（デスクトップ）";        Y = 25 },
        @{ Name = "BackupDocuments";  Text = "Documents（ドキュメント）";       Y = 50 },
        @{ Name = "BackupPictures";   Text = "Pictures（ピクチャ）";           Y = 75 },
        @{ Name = "BackupVideos";     Text = "Videos（ビデオ）";               Y = 100 },
        @{ Name = "BackupMusic";      Text = "Music（ミュージック）";          Y = 125 },
        @{ Name = "BackupDownloads";  Text = "Downloads（ダウンロード）";       Y = 150 }
    )

    $checkboxData2 = @(
        @{ Name = "BackupAppData";    Text = "AppData（辞書・テーマ）";         Y = 25 },
        @{ Name = "BackupBookmarks";  Text = "ブラウザデータ（履歴・オートフィル等）"; Y = 50 },
        @{ Name = "BackupRegistry";   Text = "レジストリ設定（IME等）";         Y = 75 },
        @{ Name = "BackupCloudDrive"; Text = "クラウドドライブ（OneDrive等）";   Y = 100 },
        @{ Name = "CloseBrowsers";    Text = "ブラウザを自動終了（推奨）";       Y = 125 }
    )

    # 左列のチェックボックス
    foreach ($data in $checkboxData) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Location = New-Object System.Drawing.Point(20, $data.Y)
        $cb.Size = New-Object System.Drawing.Size(230, 22)
        $cb.Text = $data.Text
        $cb.Name = $data.Name
        $cb.Checked = $true
        $optionGroup.Controls.Add($cb)
        $checkboxes += $cb
    }

    # 右列のチェックボックス
    foreach ($data in $checkboxData2) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Location = New-Object System.Drawing.Point(280, $data.Y)
        $cb.Size = New-Object System.Drawing.Size(250, 22)
        $cb.Text = $data.Text
        $cb.Name = $data.Name
        $cb.Checked = $true
        $optionGroup.Controls.Add($cb)
        $checkboxes += $cb
    }

    # 全選択/全解除ボタン
    $optSelectAllBtn = New-Object System.Windows.Forms.Button
    $optSelectAllBtn.Location = New-Object System.Drawing.Point(20, 200)
    $optSelectAllBtn.Size = New-Object System.Drawing.Size(100, 25)
    $optSelectAllBtn.Text = "全選択"
    $optSelectAllBtn.Add_Click({
        foreach ($cb in $checkboxes) {
            $cb.Checked = $true
        }
    })
    $optionGroup.Controls.Add($optSelectAllBtn)

    $optDeselectAllBtn = New-Object System.Windows.Forms.Button
    $optDeselectAllBtn.Location = New-Object System.Drawing.Point(130, 200)
    $optDeselectAllBtn.Size = New-Object System.Drawing.Size(100, 25)
    $optDeselectAllBtn.Text = "全解除"
    $optDeselectAllBtn.Add_Click({
        foreach ($cb in $checkboxes) {
            $cb.Checked = $false
        }
    })
    $optionGroup.Controls.Add($optDeselectAllBtn)

    #---------------------------------------------------------------------------
    # 現在のユーザー情報
    #---------------------------------------------------------------------------
    $userInfoLabel = New-Object System.Windows.Forms.Label
    $userInfoLabel.Location = New-Object System.Drawing.Point(20, 525)
    $userInfoLabel.Size = New-Object System.Drawing.Size(400, 20)
    $userInfoLabel.Text = "バックアップ対象ユーザー: $env:USERNAME"
    $userInfoLabel.ForeColor = [System.Drawing.Color]::Blue
    $form.Controls.Add($userInfoLabel)

    #---------------------------------------------------------------------------
    # バックアップ開始 / キャンセルボタン
    #---------------------------------------------------------------------------
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(350, 555)
    $okButton.Size = New-Object System.Drawing.Size(100, 35)
    $okButton.Text = "バックアップ開始"
    $okButton.Font = New-Object System.Drawing.Font("Yu Gothic UI", 9, [System.Drawing.FontStyle]::Bold)
    $okButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $okButton.ForeColor = [System.Drawing.Color]::White
    $okButton.FlatStyle = "Flat"
    $okButton.Add_Click({
        # ドライブ選択チェック
        if ($driveListBox.SelectedIndex -lt 0 -or $script:DriveList.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "バックアップ先ドライブを選択してください",
                "選択エラー",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        # フォルダ名チェック
        if ([string]::IsNullOrWhiteSpace($folderTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                "バックアップフォルダ名を入力してください",
                "入力エラー",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        # 選択されたドライブ
        $script:BackupDialogResult.TargetDrive = $script:DriveList[$driveListBox.SelectedIndex]
        $script:BackupDialogResult.BackupFolderName = $folderTextBox.Text

        # オプションを格納
        foreach ($cb in $checkboxes) {
            $script:BackupDialogResult.Options[$cb.Name] = $cb.Checked
        }

        $script:BackupDialogResult.Confirmed = $true
        $form.Close()
    })
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(460, 555)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 35)
    $cancelButton.Text = "キャンセル"
    $cancelButton.Add_Click({
        $script:BackupDialogResult.Confirmed = $false
        $form.Close()
    })
    $form.Controls.Add($cancelButton)

    #---------------------------------------------------------------------------
    # フォーム表示
    #---------------------------------------------------------------------------
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()

    return $script:BackupDialogResult
}

#===============================================================================
# 関数: Show-BackupProgressDialog
# 説明: バックアップ進捗ダイアログ
#===============================================================================
function Show-BackupProgressDialog {
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
# 関数: Show-BackupCompletionDialog
# 説明: バックアップ完了ダイアログ
#===============================================================================
function Show-BackupCompletionDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$SuccessCount,

        [Parameter(Mandatory = $true)]
        [int]$SkipCount,

        [Parameter(Mandatory = $true)]
        [int]$ErrorCount,

        [Parameter(Mandatory = $false)]
        [string]$BackupPath = "",

        [Parameter(Mandatory = $false)]
        [string]$LogPath = ""
    )

    $message = @"
バックアップ処理が完了しました。

成功: $SuccessCount 項目
スキップ: $SkipCount 項目
エラー: $ErrorCount 項目
"@

    if ($BackupPath) {
        $message += "`n`nバックアップ先: $BackupPath"
    }

    if ($LogPath -and (Test-Path $LogPath)) {
        $message += "`nログファイル: $LogPath"
    }

    $icon = if ($ErrorCount -gt 0) {
        [System.Windows.Forms.MessageBoxIcon]::Warning
    } else {
        [System.Windows.Forms.MessageBoxIcon]::Information
    }

    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "バックアップ完了",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

#===============================================================================
# 関数: Show-BackupConfirmDialog
# 説明: バックアップ確認ダイアログ
#===============================================================================
function Show-BackupConfirmDialog {
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

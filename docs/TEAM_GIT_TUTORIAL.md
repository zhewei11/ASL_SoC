# ASL_SoC 團隊 Git／GitHub 使用教學

本專案使用公開 repository、Fork、功能分支與 Pull Request 協作。成員不需要先加入
Collaborator，只要依照以下六個步驟操作即可。

專案網址：<https://github.com/zhewei11/ASL_SoC>

```text
登入 GitHub → Fork → Clone 自己的 Fork → 建立功能分支
            → Push 到自己的 Fork → 對團隊 main 提出 Pull Request
```

## 步驟 1：登入 GitHub

前往 <https://github.com> 並登入自己的 GitHub 帳號。沒有帳號的人需要先完成免費註冊。

## 步驟 2：Fork 團隊 repository

1. 開啟 <https://github.com/zhewei11/ASL_SoC>。
2. 點擊頁面右上角的 **Fork**。
3. Owner 選擇自己的 GitHub 帳號。
4. Repository name 保持 `ASL_SoC`。
5. 點擊 **Create fork**。

完成後會得到自己的專案副本：

```text
https://github.com/<你的帳號>/ASL_SoC
```

自己的 Fork 可以建立分支與 push，不會直接改動團隊的 `main`。

## 步驟 3：Clone 自己的 Fork

在自己的 Fork 頁面點擊 **Code**，複製 HTTPS URL，然後在終端機執行：

```sh
git clone https://github.com/<你的帳號>/ASL_SoC.git
cd ASL_SoC
```

設定團隊主 repository 為 `upstream`：

```sh
git remote add upstream https://github.com/zhewei11/ASL_SoC.git
git remote -v
```

Remote 的用途：

| Remote | 指向 | 用途 |
|---|---|---|
| `origin` | 自己的 Fork | Push 自己的功能分支 |
| `upstream` | `zhewei11/ASL_SoC` | 取得團隊最新版本 |

## 步驟 4：建立功能分支並修改

每次開始工作前，先同步團隊最新的 `main`：

```sh
git switch main
git fetch upstream
git merge --ff-only upstream/main
git push origin main
```

建立新的功能分支：

```sh
git switch -c feature/<你的帳號>-<功能名稱>
```

範例：

```sh
git switch -c feature/alice-usb-uart
```

確認目前不是在 `main`：

```sh
git branch --show-current
```

建議分支命名：

| 工作類型 | 分支範例 |
|---|---|
| 新功能 | `feature/alice-usb-uart` |
| 錯誤修正 | `fix/bob-protocol-crc` |
| 文件 | `docs/carol-memory-map` |
| 測試 | `test/dave-uart-loopback` |

完成修改後，執行相關檢查：

```sh
make format-check
make test
make lint
```

## 步驟 5：Commit 並 Push 到自己的 Fork

先檢查修改內容：

```sh
git status
git diff
```

只加入本次要提交的檔案：

```sh
git add <修改的檔案>
git diff --cached
git commit -m "feat: describe the change"
```

第一次 push 功能分支：

```sh
git push -u origin feature/<你的帳號>-<功能名稱>
```

範例：

```sh
git push -u origin feature/alice-usb-uart
```

這裡必須 push 到自己的 `origin`，不要 push 到 `upstream/main`。

## 步驟 6：對團隊 main 提出 Pull Request

1. 開啟自己的 Fork：`https://github.com/<你的帳號>/ASL_SoC`。
2. 點擊 **Compare & pull request**。
3. 確認合併方向：

```text
base repository: zhewei11/ASL_SoC
base branch:      main
head repository: <你的帳號>/ASL_SoC
compare branch:   feature/<你的帳號>-<功能名稱>
```

4. 填寫修改內容、測試方式與已知限制。
5. 點擊 **Create pull request**。
6. 等待至少 1 人 review 並核准。
7. Review conversation 全部處理完成後才能合併。

建議 PR 說明：

```md
## 修改內容

- 說明本次新增或修正的內容

## 驗證方式

- [ ] `make format-check`
- [ ] `make test`
- [ ] `make lint`

## 已知限制

- 若沒有，填寫「無」
```

若 reviewer 要求修改，不需要重新建立 PR。繼續在原功能分支修改並 push，原 PR 會自動更新：

```sh
git add <修改的檔案>
git commit -m "fix: address review feedback"
git push
```

## PR 合併後

同步本機與自己的 Fork：

```sh
git switch main
git fetch upstream
git merge --ff-only upstream/main
git push origin main
```

確認不再需要舊分支後，可以刪除：

```sh
git branch -d feature/<你的帳號>-<功能名稱>
git push origin --delete feature/<你的帳號>-<功能名稱>
```

## 重要規則

- 不要直接在 `main` 上開發。
- 每一項工作建立一個獨立分支。
- 不要把密碼、token、私鑰、build output、波形或大型資料集提交到 Git。
- Push 前先檢查 `git status`與`git diff --cached`。
- `main`必須透過 Pull Request 合併並取得至少 1 人核准。
- PR 增加新 commit 後需要重新 review。
- 不確定如何解決 conflict 時，不要刪除別人的修改，請在 PR 中請團隊協助。

## 最短指令清單

完成首次 Fork、Clone 與 upstream 設定後，每次工作可以依序執行：

```sh
git switch main
git fetch upstream
git merge --ff-only upstream/main
git switch -c feature/<你的帳號>-<功能名稱>

# 修改檔案並執行測試

git status
git add <修改的檔案>
git diff --cached
git commit -m "feat: describe the change"
git push -u origin feature/<你的帳號>-<功能名稱>
```

最後到 GitHub 建立 Pull Request，目標選擇 `zhewei11/ASL_SoC:main`。

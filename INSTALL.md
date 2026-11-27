# 接入/更新指令（供 AI agent 执行）

> 本文件是**给 AI coding agent 执行的指令**。员工会让你拉取并执行本文件，目的是把公司开发约定（guidelines 仓库）接入或**更新**到**当前所在的业务项目**，并配置好各 agent 工具的入口。
>
> **可重复执行**：同一套指令，首次执行 = 接入；之后每次执行 = **把 `.guidelines/` 刷新到 guidelines 最新版**，并把项目入口文件同步到当前真源文件名。**不要因为「看起来已接入过」就跳过——直接按本指令重跑即可完成更新。**
>
> **接入方式**：把 guidelines 仓库内容**复制**到项目的 `.guidelines/` 目录，并**随项目提交入库**。**不使用 git submodule。**
>
> 注意：步骤 1 在 guidelines 仓库目录（`<guidelines_dir>`）执行，其余步骤在员工的**业务项目**里执行。请严格按下列步骤操作，遇到任何不符合预期的情况先停下向员工确认，不要自行绕过。

## 变量

- guidelines 仓库地址：`git@git.example.com:dev/guidelines.git`
- 引入路径：`.guidelines`
- **`<guidelines_dir>`**：guidelines 仓库在本机的位置，**即你当前读取本 INSTALL.md 所在的仓库目录**。后续所有步骤中以它代指，不写死具体路径。
- **唯一真源入口**：`.guidelines/GUIDELINES.md`（约定索引，内含指向各约定的阅读清单）。**任何入口文件都只指向它，不逐个罗列约定文件**——清单内容统一由它维护。
- **项目侧入口**（随项目提交，均为指针）：根 `AGENTS.md` — **基础规范入口**，各 agent 工具按文件名自动读取，内容为指向唯一真源入口的指针。
- **旧真源名（已弃用）**：`.guidelines/AGENTS.md`。真源入口曾叫 `AGENTS.md`，为避免与各业务项目根目录中供各 agent 工具按文件名自动读取的 `AGENTS.md` 指针混淆，已改名。**更新时若发现入口/清单残留旧真源名，按「步骤 4」替换。**
- **旧版接入块（已弃用）**：曾写入各项目根 `AGENTS.md` 的逐文件必读清单块（依次列出 GUIDELINES.md、agent.md、git.md 等）。现改为唯一入口制，更新时按「步骤 4」整块替换。

## 开始前：判定执行模式

1. 确认当前目录是 git 仓库根目录：`git rev-parse --show-toplevel` 的输出应等于当前目录。
   - **是** → 执行全部步骤。
   - **当前目录不是 git 仓库** → **先停下询问员工**是否仍在此目录接入，并说清差别：非 git 目录下只复制 `.guidelines/`、同步入口文件，**没有** `.gitignore` 配置和提交步骤。员工确认继续后才往下做；不确认则终止。
   - 在 git 仓库中、但当前目录不是仓库根目录 → 停下向员工确认，不要在子目录里接入。
2. （仅 git 仓库）工作区应干净：`git status --porcelain` 无输出。若不干净，先让员工处理（提交或 stash）再继续——**不要把员工未提交的改动混进本次 commit**。

## 步骤 1：获取最新 guidelines

在当前目录（即 `<guidelines_dir>`，本文件所在的 guidelines 仓库）执行：

```bash
git pull
git log -1 --oneline   # 记下本次版本，供最终报告使用
```

若当前目录不是 guidelines 仓库，或 pull 失败（本地有未提交改动、网络问题等），先停下向员工确认，不要自行绕过。

## 步骤 2：（仅 git 仓库）移除 submodule 残留（若曾以 submodule 接入）

若项目此前以 submodule 方式接入过（`.gitmodules` 中含 `.guidelines` 条目）：

```bash
git submodule deinit -f .guidelines
git rm -f .guidelines
rm -rf .git/modules/guidelines   # git rm 之后仓库里残留的 submodule 元数据
# .gitmodules 若已被清成空文件，一并删除
```

未曾以 submodule 接入（首次接入，或此前已是复制模式）→ 跳过本步骤。

> `.guidelines/` 以普通文件提交入库正是现行方式，无需移出版本控制。

> 非 git 目录（「开始前」已获得员工确认）→ 跳过本步骤及所有标注「仅 git 仓库」的步骤。

## 步骤 3：把 `.guidelines/` 整体替换为最新内容

`.guidelines/` 必须是 guidelines 仓库的原样副本，**不允许本地改动**——要改约定就提交回 guidelines 仓库，由大家重新执行本指令获取。因此更新采用整体替换，同时天然清掉上游已删除的旧文件。

执行前先确认 `.guidelines/` 内没有员工的手工改动痕迹；若有，停下确认，不要直接覆盖。git 仓库中可直接用 `git status .guidelines` 检查——`.guidelines/` 已入库，本地改动会如实显示。

```bash
rm -rf .guidelines
mkdir .guidelines
rsync -a \
  --exclude='.git' \
  --exclude='.gitignore' \
  --exclude='INSTALL.md' \
  --exclude='README.md' \
  --exclude='.claude' \
  --exclude='.DS_Store' \
  --exclude='agent_docs' \
  <guidelines_dir>/ .guidelines/
```

> 排除项：git 管理文件、guidelines 仓库自身的 gitignore 与本地配置、本安装指令、面向人的 README——这些不需要出现在业务项目里。
>
> Windows 等没有 rsync 的环境，用系统等价的目录复制命令（如 PowerShell `Copy-Item` / `robocopy`）完成同样的事，排除项与本列表相同。

复制后确认 `.guidelines/GUIDELINES.md` 可读、内容与 `<guidelines_dir>` 下最新版本一致。

## 步骤 4：同步 agent 工具入口（首次与更新都执行）

目的：让各工具读到约定。**约定唯一真源入口是 `.guidelines/GUIDELINES.md`**，项目侧只放指针、不复制内容：

- 根 `AGENTS.md` 是基础规范入口，各工具按文件名读取，内容为指向唯一真源入口的指针。

**通用迁移规则**：

- 入口文件里所有指向旧真源名 `.guidelines/AGENTS.md` 的字符串，一律替换为 `.guidelines/GUIDELINES.md`（没有就跳过）。
- 根 `AGENTS.md` 里的**旧版接入块**（以「本项目遵循公司统一开发约定，约定文件位于 `.guidelines/` 中」开头、逐个列出 agent.md / git.md 等文件的必读清单），整块替换为下方的现行接入块。
- 根 `AGENTS.md` 的接入块为**不含本地约定行的旧版本**（有 `@.guidelines/GUIDELINES.md` 但没有 `@.guidelines-local/GUIDELINES-LOCAL.md`）→ 整块替换为下方的现行接入块。

### a) 根 `AGENTS.md`（基础规范入口，所有 agent 工具）

> 这个文件**必须叫 `AGENTS.md`**（各工具按文件名识别），**不要改名**；它与 `.guidelines/` 内的真源 `GUIDELINES.md` 是两个不同文件——前者是项目内指针，后者是真源。

1. 按通用迁移规则替换旧真源名、替换旧版接入块；
2. 若文件尚不含下方现行接入块 → 在文件末尾追加（保留员工其它内容，不要整篇重写）：

```markdown
# 项目约定

本项目遵循统一开发约定，**唯一入口是 `.guidelines/GUIDELINES.md`**。开始任何开发工作前，必须先完整阅读该入口，并按其中的约定分类读取各规范文件、严格遵守。

@.guidelines/GUIDELINES.md

当这些约定与你的默认行为冲突时，以约定为准。
```

### b) 已存在根 `CLAUDE.md`？合并进 `AGENTS.md`

检查项目根目录是否存在 `CLAUDE.md`：

1. **不存在** → 跳过本小节。
2. **存在** → 告知员工：新版 Claude Code 已支持按文件名读取根 `AGENTS.md`——`AGENTS.md` 是更符合行业标准、各 agent 工具统一遵循的入口规范，旧的 `CLAUDE.md`（旧版接入时通常只写一行 `@AGENTS.md`）已不再需要，可**合并进 `AGENTS.md` 后删除**。询问员工**是否合并**：
   - **同意合并** → 把 `CLAUDE.md` 中的项目特有内容**总结后并入**根 `AGENTS.md`：跳过指向本指南入口的指针行（如 `@AGENTS.md`），其余内容（含对项目文档的 `@` 引用）保留，不整篇重写。若除指针行外没有其它内容，则无需并入。随后删除 `CLAUDE.md`——git 仓库用 `git rm CLAUDE.md`（一并暂存删除），非 git 目录用 `rm CLAUDE.md`。
   - **不同意合并** → 保持 `CLAUDE.md` 原样，不修改、不删除。

## 步骤 5：初始化本地个人约定目录 `.guidelines-local/`（首次与更新都执行）

`.guidelines-local/` 存放开发者个人的工作习惯文档，目录与入口文件用法见下方模板：

- `.guidelines-local/GUIDELINES-LOCAL.md` **已存在 → 完全不动**。本地目录是开发者个人内容，任何更新流程都不得触碰；
- 不存在 → 创建 `.guidelines-local/` 目录并写入模板入口文件（内容照抄下方模板，不要增删）：

```markdown
# 本地个人约定

本目录（`.guidelines-local/`）存放你——本机开发者——个人的工作习惯文档，agent 工具会自动读取并遵循。目录已被 gitignore，不入版本控制：每位开发各自维护，内容互不相同、互不共享。

## 怎么用

1. **简单习惯直接写**：把内容直接写在下面「我的个人约定」一节。
2. **新增文件必须手动挂到本文件**：往本目录添加新文档（如 `my-style.md`）后，**必须在本文件中加一行 `@` 引用，agent 才会读到它**——`@` 不支持通配符，放在目录里的文件不会被自动发现。例如新增 `my-style.md` 后，在「我的个人约定」一节加一行 `@my-style.md`。文件多就并列多行 `@`。

   也可以直接让 agent 代劳，对它说：「我在 `.guidelines-local/` 新增了 xxx.md，请在 `GUIDELINES-LOCAL.md` 里用 `@` 把它挂上」。

> 引用深度限制：`@` 嵌套有上限，**被引用的文件里只引用一层**——不要再 `@` 其它文件。

## 我的个人约定

（在此编写，或在此添加 `@` 引用）
```

在`AGENTS.md`中增加以下说明：
```markdown
`.guidelines-local/GUIDELINES-LOCAL.md` 是本机开发者的个人本地约定（目录不入库、每人各自维护）。若该文件存在，阅读并遵循其中内容；**与公司约定冲突时，以这份约定为准**。

@.guidelines-local/GUIDELINES-LOCAL.md
```

## 步骤 6：（仅 git 仓库）配置 .gitignore（仅 `.guidelines-local/`）

`.guidelines/` 入库，`.guidelines-local/` 不入库：

1. `.gitignore` 不存在 → 新建；
2. **删除**其中忽略 `.guidelines` 的条目（`.guidelines/`）——旧版接入方式曾要求加入，现在 `.guidelines/` 需要入库，残留该条目会导致整个目录被 git 忽略、无法提交；
3. 其中尚无忽略 `.guidelines-local` 的条目 → 追加一行 `.guidelines-local/`（已有则跳过，不要重复添加）。

## 步骤 7：（仅 git 仓库）提交

`.guidelines-local/` 不入库，进入版本控制的是 `.guidelines/` 全部内容、入口文件和 `.gitignore`（以及步骤 2 的 submodule 移除，其改动已随 `git rm` 进入暂存区）：

```bash
git add .guidelines .gitignore AGENTS.md   # 仅 add 本次实际改动的文件，不存在的不要 add；CLAUDE.md 的删除已在步骤 4b 用 git rm 暂存
```

commit message 按 git.md 约定（中文、写行为）：

- 首次接入：`chore: 接入公司开发约定（.guidelines 复制到本地并入库）`
- 从 submodule 迁移：`chore: guidelines 由 submodule 改为本地复制入库`
- 纯更新：若 `.guidelines/`、入口文件与 `.gitignore` 均无变化，则**无需提交**；有变化则正常提交（如 `chore: 更新公司开发约定至 <步骤 1 记下的 commit>`）。

**不要替员工 `git push`**——告知员工改动已提交，由员工自行 review 后推送。

## 步骤 8：清理并报告

安装已完成（版本号已在步骤 1 记下）。**删除临时目录中的 guidelines 仓库**——它是为执行本指令而临时 clone 的，用完即弃，下次更新重新 clone 即可：

```bash
rm -rf <guidelines_dir>
```

> 仅删除本次临时 clone 的目录。若你是从本机已持久存在的 guidelines 副本读取本文件（并非本次临时 clone），则不要删除，保持原样。

简要告诉员工：

- 本次是接入还是更新；`.guidelines/` 已刷新为 guidelines 的哪个版本（步骤 1 记下的 commit）。
- 入口文件 `AGENTS.md` 是否有改动；（若发生）submodule 已移除、`.gitignore` 中旧的 `.guidelines/` 忽略条目已清理。
- 项目原有根 `CLAUDE.md` 的话：本次是否已合并进 `AGENTS.md` 并删除，还是按员工选择保留原样。
- `.guidelines-local/` 本次是新建模板还是已有内容被保留（已存在时必须原样未动）。
- **后续如何更新**：`.guidelines/` 随仓库提交传播，**新克隆的项目已含 `.guidelines/` 与入口文件，无需重新接入**。更新到最新版仍需**重新执行一遍本 INSTALL.md**——刷新产生的改动要按步骤 7 提交。
- **可选**：如果想让更新更便捷，可以让 agent 把本 INSTALL.md 安装成所用工具的 skill。不同 agent 工具的 skill 规范各不相同，可按各自规范制作——需要的话直接对 agent 说即可。

## 步骤 9：询问是否探测 gt 与 SSH（可选，安装收尾后执行）

步骤 8 的报告发完后，主动问员工一次：

> 需要我顺手验一下 `gt` 和 SSH 连接吗？只看能不能用，不改任何东西；有问题我会告诉你需要配什么。

- 不需要 → 结束，不再追问。
- 需要 → 只做下面两项（只读，不装、不改、不打印密钥原文）：

1. `gt`：`gt --version`、`gt auth whoami`（或等价的只读登录查询），确认已登录且实例是 `https://git.example.com`。未安装/未登录/权限不足 → 告诉员工要装 `gitea-cli`，或在 `~/Library/Application Support/gitea-cli/` 重新登录并确认 token scope。
2. SSH：`tailscale status` 是否已登录（edge/app 走 tailscale），再依次（间隔 `sleep 3~6`）跑
   ```bash
   ssh root@10.0.0.1 'echo ok'   # edge
   ssh root@10.0.0.3 'echo ok'   # app
   ```

最后一行结论即可：都正常就说一句正常；不正常的逐条说明是 tailscale 未登录、key/授权缺失，还是需员工确认访问方式。

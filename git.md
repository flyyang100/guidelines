# Git 约定

## 服务器

- 使用 gitea 作为 git remote server，地址是 `https://git.example.com`；开发机已配好连接服务器的 SSH key，可直接连接。
- CLI 工具是 `gt`（gitea-cli 1.2.0，`~/.local/bin/gt`），已登录 `dev@https://git.example.com`（默认实例），token scope：`write:repository`、`write:issue`、`read:user`、`read:organization`。
- `gt` 的账号与凭据在 `~/Library/Application Support/gitea-cli/`（目录 700，文件 600）。
- 子命令：`repo`、`issue`、`pr`、`run`、`runner`、`secret`、`workflow`、`branch`、`release`、`api`；输出加 `--json`/`--jq`，写操作可加 `--dry-run`。
- CLI 未封装的端点用 `gt api /<path>`，路径相对 `/api/v1`。
- 实例的版本与备份见 [server.md](server.md)。
- 如果 `gt` 的权限或者 access token 没有配置，你需要询问员工来配好。

## 提交约定

### 0. 一句话原则

**git log 是留给未来接手者的上下文**：每个 commit 都要做到——只看 log，就能知道做了什么（行为）、为什么（约束与结论）、能否安全回滚（原子）。

### 验收标准

- **回滚安全**：任意一个 commit 可以被 `git revert` 单独回滚，不牵连其他意图。
- **可追溯**：任何一个行为变化（包括 bug）都能沿历史定位到引入它的 commit，并读到当时的意图与约束。

### 1. 原子提交：一个 commit 只做一件事

- 一个 commit = 一个意图：一个功能、一个修复、一次重构、一处样式调整。
- 开发中顺手改到的无关内容（重构时看到的小 bug、顺手调整的样式）**必须拆成独立 commit**，哪怕只有几行。禁止「重构 + 功能 + 顺手改个样式」混在一个 commit。
- 提交前自查 `git status` 和 `git diff --stat`：本 commit 涉及的文件是否都属于同一个意图；不属于就拆出去。
- **回滚测试**：问自己「revert 这个 commit，代码库是否恰好失去一个意图？」答案是否定，就拆分。
- 大功能可以拆成多个 commit（如 数据模型 → 接口 → 前端对接），但每个 commit 必须是可构建的、完整的意图步骤。
- 测试与实现同 commit（fix 必须附回归测试）；OpenAPI 导出等知识同步随同意图的代码改动提交；纯文档改动单独 `docs` commit。

### 2. 提交消息：写结论，不写流水账

格式（conventional commits，与既有历史一致）：

```
<type>(<scope>): <subject>

<body>
```

- **subject 写行为，不写文件**：回答「代码库的行为发生了什么变化」，禁止「修改了 order.py、schema.py」这类文件清单。
  - ✓ `fix(order): 下单金额为负时拒绝并返回业务错误`
  - ✓ `feat(pay): 接入支付宝当面付下单`
  - ✓ `refactor(auth): 抽取统一登录态校验（行为不变）`
  - ✗ `修改订单相关文件`、`update code`
- **body 写为什么**：什么不对、违反哪条约定、依据什么结论。subject 一句话说不清的，都进 body。
  - ✓ `下单接口未校验金额正负，负数订单可绕过支付校验，违反 app.md 输入校验约定；补上校验并新增回归测试。`
  - ✗ `原来这里有一个优惠券功能现在删除了` ——这是对 diff 的复述，不是结论。
  - 结论式写法：`移除优惠券模块——已被会员折扣替代，调用方均已迁移。`
- **记录持久结论，不记录过程**：commit 之后，body 里的每句话都应仍然成立；只描述「改了什么操作」的文字会过期。
- 重构类改动在 subject 注明「行为不变」——回滚安全性直接可见。
- type 取值：`feat` / `fix` / `refactor` / `perf` / `docs` / `style` / `test` / `chore` / `revert`；scope 用受影响的模块或应用（如 order、pay、workflow）。
- 语言：中文；subject 一句话，尽量 ≤ 80 字。
- 如果一件事用一段 body 解释不清，说明这个 commit 不原子——回到第 1 条拆开。

### 3. 禁止进入 commit 的内容

- 密钥、密码、token；含密钥的 `config.toml`（见 app.md）；`.venv/`、`node_modules/`、构建产物；`agent_docs/`（见 agent.md）。
- 调试残留：`print` / `console.log`、临时注释、硬编码的测试数据。
- 与 commit 意图无关的文件。
- 提交前 `git diff` 自查一遍。

### 4. 分支规范

- 分支命名按 `<type>/<需求名>`（如 `feat/alipay-pay`、`fix/order-negative-amount`）
- 分支合并需要走PR。
- 合并PR时使用`squash`来精简提交。注意message仍需要遵守上面的提交约定。


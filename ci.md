# CI 标准

## 两条流水线

| 文件 | 触发 | 阻塞合并 | 内容 | 单 job 上限 |
|---|---|---|---|---|
| `.gitea/workflows/ci.yml`（fast） | PR 创建/更新（目标默认分支） | **是**：五个 job 全绿才合 | lint / typecheck / test / openapi-drift / build | 20 分钟 |
| `.gitea/workflows/ci-slow.yml`（slow） | push 默认分支、手动 | 否 | security-scan | 20 分钟 |

- runner：开发机 colima 里的 act_runner 容器（host 模式），2 核 / 1.9G，job 串行；`runs-on` 写 `ubuntu-latest`。
- fast CI 用 `concurrency: group: ci-${{ github.ref }}` + `cancel-in-progress: true`：同一 PR 新 push 取消旧 run。
- slow CI 也用 `concurrency: group: ci-slow-${{ github.ref }}` + `cancel-in-progress: true`：连续 merge 时只保留最新一次扫描，避免两个 run 同时占满 runner 的 2 个 slot。
- slow CI 红 = 待修，不是可忽略——长期红等于没有这条流水线。
- **分支保护必须与 fast CI 的 job 一一对应**：5 个 context（`CI / <job> (pull_request)`）全部 required，禁直推默认分支；没有分支保护的 CI 只是仪表盘，不是门禁。

## fast CI

job 名称固定 `lint` / `typecheck` / `test` / `openapi-drift` / `build`；前四者并行，`build` 为 `needs: [lint, typecheck, test]`（契约检查与构建无依赖，不进 `needs`，避免拉长关键路径）。

| job | 前端（`frontend/`） | 后端（`backend/`） |
|---|---|---|
| lint | `npm run lint` | `ruff check .`（含 `scripts/`：运维脚本会被直接在生产/qa 执行） |
| typecheck | `npm run typecheck`（tsc） | `mypy app`（入库脚本的仓库把 `scripts` 一并纳入） |
| test | `npm test`（vitest run） | `pytest tests -q --cov=app --cov-report=term-missing` |
| openapi-drift | — | 用 `requirements.txt` 建 venv → 导出 `app.openapi()` → `diff -u openapi.json` |
| build | `npm run build`（vite） | `python -m compileall -q app` |

**为什么 openapi-drift 在 fast 而不在 slow**：契约漂移是「改接口忘重导」这一类确定性错误，PR 阶段就该拦；放到 merge 后才报只是迟一步的坏消息（实例：repo-a PR #21、repo-b 接入前已漂 3 处）。没有前端（纯 backend 仓库）就没有 `lint`/`test` 的前端步骤，job 名不变。

## slow CI

| job | 内容 |
|---|---|
| security-scan | 前端 `npm audit --omit=dev --audit-level=high`；后端 `pip-audit -r requirements.txt --disable-pip --no-deps --desc` |

- 审计口径只卡运行时依赖：进构建产物的是 `dependencies`；`devDependencies` 的公告不作门禁（vite / vitest / typescript-eslint 互相锁大版本，picomatch 最新发布版即在受影响范围），清它们要整轮大版本升级。
- **`pip-audit` 必须带 `--disable-pip --no-deps`**：它默认会起 `pip install --dry-run` 重新解析整棵依赖树，绕过 uv 缓存、直接联网；runner 到 PyPI 抖动时会挂到 20 分钟 job 上限（实例：repo-c run 831/832）。`requirements.txt` 已是全量固定版本，两个 flag 一起去掉解析层，只审计列出的固定版本（实测 2 个包 1.1s）。
- **不做每日定时**：同一份 commit 重扫锁定版本的依赖没有增量；真有新 CVE 会在下一次 merge 或手动触发时暴露。需要重扫用 `workflow_dispatch`。
- **不与 fast 重复**：fast 里已有的检查不在 slow 里再跑一遍（merge 后重跑同一份代码没有增量）。

## 环境不变量

| 项 | 要求 | 原因 |
|---|---|---|
| Python | uv 托管的 3.14（`uv venv .venv-ci --python 3.14`） | 与生产一致；runner 自带 python3 是 3.12，只用来装 uv |
| 包索引 | `PIP_INDEX_URL` 与 `UV_INDEX_URL` 都指向国内镜像源 | tuna 在 colima/TUN 代理下会「200 后卡死」；uv 不读 `PIP_INDEX_URL` |
| runner 工具链 | uv / pip-audit / CPython 3.14 预装进 `ci-runner` 镜像 | job 容器一次性，不预装就每个 job 重下 35MB Python 并 `pip install uv` |
| 依赖缓存 | `/root/.cache`、`/root/.npm`、`/root/.local` 用命名卷同时挂给 runner 与 job 容器 | 缓存跨 job / 跨 repo 命中，只有新增依赖才联网下载 |
| npm 源 | 默认 registry（`registry.npmjs.org`） | `package-lock.json` 的 `resolved` 指向官方源，换镜像会整体改写 lockfile |
| 依赖清单 | `requirements.txt` 与 `requirements-dev.txt` 分离 | 各 job 装法不同：lint 只装 dev、typecheck 两份都装、test 装 `requirements.txt`（pytest 在其中）+ `pytest-cov`、openapi-drift 只装 `requirements.txt` |

## 配置来源

- 干净 checkout 没有 `config.toml`（含密钥，不入库）。
- **import 期不得读密钥类配置**：DB engine / session factory 懒创建（`get_engine()` / `get_session_factory()`），`lifespan` 关闭调 `dispose_engine()`。违反后果：schema 导出、lint 这类不连库的步骤被密钥卡死。
- 需要配置的步骤（测试、drift 导出）用入库的无密钥测试配置 `backend/tests/config.test.toml`，经 app 自己的 `*_CONFIG` 环境变量指定；`tests/conftest.py` 与 CI 共用同一份（配置失效先被测试发现）。
- `config.toml.example` 是给人抄的部署模板，**不作配置来源**。

## 契约同步

- 导出 `openapi.json` 不连库；配置内容不影响 schema。
- **freeze 或升级 fastapi / pydantic 后必须重导 `openapi.json`**：schema 由框架版本生成，同一份代码在不同版本下表述不同（dict 字段的 `additionalProperties`、`UploadFile` 的 `format` / `contentMediaType`、`ValidationError` 的 `input` / `ctx` 等），不重导 drift 必红。

## 已知缺口

| 项 | 现状 |
|---|---|
| DB 迁移漂移（ORM 模型 ↔ 真实库） | 无 CI 检查；防线是发布前对生产库只读体检 |
| devDependencies 高危公告 | 不进审计门禁；需 vite 6+ / vitest 4+ 大版本升级才能清 |
| 前端 lint / test 工具链 | 早期仓库（repo-b / repo-d / core-api / repo-e）前端只有 `build`，无 eslint / vitest；这类仓库的 `lint` / `test` 只覆盖后端，前端为 `typecheck` + `build`，接入工具链属独立议题 |
| `E501`（行宽） | 存量长行集中的仓库（如 repo-b：协议报文/日志模板整体字符串）暂 `ignore = ["E501"]`，其余规则全开；统一格式化属独立议题 |
| 无 workflow 的仓库 | repo-d / core-api / repo-e 待接入；接入前其 `openapi.json` 无人校验，靠改接口时人工重导 |
| 测试依赖在运行时清单 | pytest / pytest-asyncio 在 `requirements.txt` 里，生产 venv 会装上；`requirements-dev.txt` 只放 ruff / mypy |
| 时序敏感用例 | 依赖真实时钟的用例（如 repo-b 的轮次超时/媒体停播）在 2 核 runner 上余量偏薄；接入时须实测，必要时改用例而不是放宽闸门 |

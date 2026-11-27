# 日志规范

本文约定应用如何**记录可排查的日志**。目标只有一个：当线上出问题（卡顿、与三方系统交互异常、SDK 报错/超时）时，**仅凭日志就能还原"这一次"发生了什么**，而不必复现或加日志重发。

与 [app.md](app.md) 配合：app.md 定义日志文件的**分类与格式**（`logs/` 下五类日志、按天拆分、一行文本前缀格式），本文定义**留存、写什么、怎么写、怎么用**。**留存约定（唯一真源）**：按天拆分，明文保留 7 天，超过 7 天的压缩归档，压缩件保留 3 个月。

> 适用范围：默认适用于所有 backend 应用（Flask / FastAPI）；前端按[第 11 节](#11-前端h5错误与性能上报)做错误与性能上报。
>
> **优先级**：本文是**默认生效**的通用约定。项目内以 `AI-` 开头的 `.md`（如 `AI-LOGGING.md`、`AI-README.md`）若对日志另有约定，**以项目约定为准**——与 [GUIDELINES.md](GUIDELINES.md#优先级) 的优先级规则一致。下文中的"必须""默认"等表述，都是在项目未另行约定时的缺省要求。

---

## 0. 一句话原则

**没有 `trace_id` 的日志近乎无用**，**没有耗时的日志查不了卡顿**，**没有堆栈的 error 等于没记**。下面每一节都是为这三句话服务。

---

## 1. 日志行格式：文本前缀 + 末尾 kv

在 app.md 既有的一行文本前缀之后，**把结构化字段以 `key=value` 追加到消息末尾**。人能直接读，`grep`/`awk` 能过滤，无需引入额外日志系统。

```
%(asctime)s [%(threadName)s] %(levelname)s [%(module)s:%(lineno)d]: <人类可读消息> k1=v1 k2=v2 ...
```

示例：

```
2026-06-30 12:00:01.123 [MainThread] INFO [order:42]: 创建订单 trace_id=a1b2c3d4 user_id=1001 order_id=20260630001 duration_ms=83 status=ok
2026-06-30 12:00:02.880 [MainThread] WARNING [llm.chat:88]: LLM 调用慢 trace_id=a1b2c3d4 provider=openai model=gpt-4o duration_ms=8120 retries=1 status=ok
2026-06-30 12:00:05.001 [worker-3] ERROR [pay.alipay:120]: 支付回调验签失败 trace_id=e5f6 provider=alipay error_type=biz duration_ms=12 status=error
```

**kv 字段写法规则：**

- 时间戳精确到**毫秒**且带**时区**（`%(asctime)s` 默认无毫秒，需在 formatter 里配 `datefmt` + `%(msecs)03d`，或直接用带毫秒的格式）。做延迟对比时毫秒是底线。
- key 用 `snake_case`，**全应用统一**同一含义用同一 key（见[第 12 节字段字典](#12-标准字段字典)）。不要 `userId`/`uid`/`user` 混用。
- value 含空格、`=`、换行时**必须加引号并转义**（如 `msg="bad request"`）。多行内容（堆栈、大 payload）见[第 6 节](#6-异常与超时)、[第 8 节](#8-噪音控制与截断)。
- value 为空也要占位（`order_id=-` 或省略该 key），不要写出 `order_id=None` 之类噪音——除非 None 本身是排查线索。
- 布尔/枚举用稳定字面量：`status=ok|error|timeout`、`cache=hit|miss`。

> 封装一个 `kv(**fields)` 辅助函数统一拼接与转义，禁止各处手写字符串拼接。

---

## 2. trace_id：贯穿一切的链路 ID（最高优先级）

一次请求会在 `request.log` 立案、在 `sql.log` 查库、在 `llm.log` 调模型、出错时在 `error.log` 报错。**没有一个 ID 把它们串起来，五个日志文件就是五份互不相关的流水账。**

规则：

1. **入口生成**：每个请求进入时生成一个 `trace_id`（短随机串即可，如 8~16 位 hex / uuid4 去横线），存入请求级上下文。
   - 若上游（网关 / 前端）已在请求头带了 `X-Trace-Id`，**沿用它**，不要重新生成。
2. **全程注入**：该请求产生的**所有**日志行都必须带上这个 `trace_id`——包括它派生的子线程、异步任务、`run_in_executor` 等。用日志 `Filter` + 上下文变量自动注入，**不要靠每个调用点手传**。
   - Flask：`flask.g` 或 `contextvars` 存 trace_id，自定义 `logging.Filter` 从中读取并写入 `record`。
   - FastAPI：必须用 **`contextvars.ContextVar`**（async 下 `g` 不可用），在中间件里 `set`，Filter 里 `get`。注意跨 `await`/线程池边界时 contextvars 的传递（`asyncio` 默认会拷贝上下文，`run_in_executor` 需手动透传）。
3. **回传前端**：响应头返回 `X-Trace-Id`。用户报障时带上它，你能秒级定位整条链路。
4. **传递到上游**：调用三方时，把 `trace_id` 放进出站请求头；同时**记录三方返回的 request-id**（见[第 5 节](#5-三方系统交互llm-http-rpc-等)），形成跨系统链路。
5. **后台任务**：定时任务 / 消费者 / 脚本没有"请求"，**在任务开始时自行生成 `trace_id`**，并额外带 `job_id`（见[第 9 节](#9-多进程异步与定时任务)）。

---

## 3. 日志级别使用约定

格式里有 `levelname`，但级别若没有统一标准，过滤就失去意义。按下表用：

| 级别 | 何时用 | 进哪个文件 |
|---|---|---|
| `DEBUG` | 开发期排查细节（变量值、分支走向）。**生产默认关闭。** | app.log（生产不输出） |
| `INFO` | 正常业务里程碑：请求起止、关键状态变更、外部调用成功、任务起止。 | app.log（按类别另进 request/sql/llm.log） |
| `WARNING` | 还能继续，但不正常：命中慢阈值、触发重试、降级、可恢复的预期异常、用量逼近上限。 | app.log（+ error.log 视情况） |
| `ERROR` | 单次操作失败、需要人关注：未捕获异常、三方调用最终失败、超时、数据不一致。**必须带堆栈或 error_type。** | app.log + error.log |
| `CRITICAL` | 影响面大、需立即介入：启动失败、依赖完全不可用、数据损坏风险。 | app.log + error.log |

**关键纪律——区分预期业务错误与意外错误**：
- 用户输入校验失败、余额不足、订单状态不对等**预期业务结果**，用 `WARNING`/`INFO` 记并标 `error_type=biz`，**不要进 error.log**。
- 只有**意外/系统级**错误（异常、超时、依赖故障）才记 `ERROR`。
- 这条直接决定部署后的冒烟检查（"grep app.log 自部署起有无新增 ERROR"）是否有效——error.log 一旦被业务噪音淹没，告警就失灵了。

---

## 4. 卡顿排查：耗时与慢日志

查卡顿的前提是**每个可能慢的环节都记了耗时**。

1. **必记 `duration_ms`** 的环节：每个请求（总耗时）、每次外部调用（DB / Redis / LLM / 三方 HTTP）、明显耗时的内部计算。
2. **慢阈值自动升级**：超过阈值的操作**自动从 INFO 升为 WARNING**，并标 `slow=true`，便于单独检索"慢日志"。各项目按实际定阈值并写进项目 `AI-*.md`，给一组缺省起点：

   | 操作 | 默认慢阈值 |
   |---|---|
   | HTTP 请求总耗时 | > 1000 ms |
   | 单条 SQL | > 200 ms |
   | Redis 单次 | > 50 ms |
   | 三方 HTTP / RPC | > 2000 ms |
   | LLM 调用 | > 5000 ms |

3. **请求级耗时落 `request.log`**：每个请求结束记一行，至少含 `trace_id method path status_code duration_ms`。
4. **慢 SQL 落 `sql.log`**：ORM 层记 SQL 执行耗时；命中阈值的标 `slow=true`。注意脱敏（见[第 7 节](#7-敏感信息脱敏)），SQL 参数里常含真实数据。
5. 不要只在出错时记耗时——**正常但慢**才是卡顿排查的主战场。

---

## 5. 三方系统交互（LLM / HTTP / RPC 等）

对**所有**外部系统（不止 LLM）的调用，用统一字段记一行"出站调用"日志（成功进对应类别日志或 app.log，失败进 error.log）。LLM 专项进 `llm.log`。

统一字段：

| 字段 | 含义 |
|---|---|
| `trace_id` | 链路 ID |
| `provider` | 目标服务标识，如 `openai` / `alipay` / `sms-gateway` |
| `endpoint` | 调用的接口/方法，如 `chat.completions` / `trade.query` |
| `duration_ms` | 本次调用耗时 |
| `status` | `ok` / `error` / `timeout` |
| `retries` | 已重试次数（首次为 0） |
| `upstream_id` | 三方返回的 request-id / trace-id（用于找三方对账，**务必记**） |
| `http_status` | HTTP 状态码（如适用） |

**LLM 调用额外记**（`llm.log`，沿用 app.md：内容、应答、token）：`model`、`prompt_tokens`、`completion_tokens`、`total_tokens`、`finish_reason`；请求/应答正文**脱敏 + 截断**后记录（见第 7、8 节）。

要点：
- **超时与报错分开标**（`status=timeout` vs `status=error`），二者排查方向完全不同——超时查网络/对端/我方阈值，报错查参数/鉴权/对端逻辑。
- **每次重试都记一行**（带 `retries=N`），不要只记最终结果；否则看不出"慢"是因为重试。
- 记下**实际生效的超时配置**（`timeout_ms=`），排查时才知道是不是我方阈值设太短。

---

## 6. 异常与超时

1. **ERROR 必须带完整堆栈**：Python 用 `logger.exception(...)` 或 `logger.error(..., exc_info=True)`。**禁止只写一句 `logger.error("失败")`** 而丢掉堆栈和上下文。
2. **堆栈的多行处理**：堆栈跟在该 ERROR 行之后输出（标准 logging 行为即可），保证它和触发它的那行 `trace_id` 紧邻，可被一起检索到。
3. **标 `error_type`** 便于分类检索，至少区分：`timeout`（超时）、`conn`（连接失败）、`biz`（预期业务错误）、`integrity`（数据/约束）、`upstream`（三方返回错）、`unknown`。
4. **超时可独立检索**：所有超时统一 `status=timeout`/`error_type=timeout`，并带 `timeout_ms=` 实际阈值。
5. **不要重复记同一个错**：异常在底层记一次（带堆栈），向上抛时让顶层统一处理，中间层不要每层都 `log.error` 一遍——否则一个错误在 error.log 里出现五遍，淹没真正的并发问题。约定：**谁最终处理谁记录**，中间层最多 `WARNING` 加一句上下文后重抛。

---

## 7. 敏感信息脱敏

密钥、密码与真实用户数据禁止写进日志，但 `llm.log`/`sql.log`/`request.log` 天然会碰到。必须有**具体脱敏规则**，否则这条红线必被踩。

- **绝不记录**（任何级别）：密码、token / api-key / secret、完整银行卡号、短信验证码、Cookie/Session 原文、Authorization 头。
- **掩码后记录**：手机号 `138****8000`、身份证 `110***********1234`、邮箱 `a***@x.com`、姓名（保留姓）。
- **统一脱敏函数**：提供 `mask(value, kind)` 工具，在日志输出层兜底脱敏；不要指望每个调用点记得脱敏。
- **请求/响应体**：`request.log` 记响应体前 N 字符前先过脱敏；LLM 的 prompt/应答同样先脱敏再截断。
- 拿不准某字段算不算敏感时，**按敏感处理**（掩码），别赌。

---

## 8. 噪音控制与截断

日志太多 = 没有日志。控制噪音和缺日志同样重要。

- **健康检查不刷屏**：`GET /ping` 等探活请求不记 request.log（或降到 DEBUG）。
- **大 payload 截断**：请求/响应体、LLM 正文、长结果统一截断（如 500~1000 字符），并标 `truncated=true` + 原始长度 `len=`。`request.log` 现有的"前 500 字符"约定推广为通用规则。
- **循环内不要逐条打**：批处理用聚合日志（"处理 1000 条，成功 998，失败 2 trace_id=.."），失败明细单独记。
- **高频路径降级**：可预见会高频触发的日志放 DEBUG，或加采样/限流。
- **同一错误不刷屏**：重试/轮询里的可恢复失败用 WARNING 且避免每次满堆栈，最终失败再 ERROR 带堆栈。

---

## 9. 多进程、异步与定时任务

这是最容易丢日志/串日志的地方，必须按下面写：

1. **gunicorn 多 worker 写同一文件**：多个进程同时用 `TimedRotatingFileHandler` 切割**会丢日志、切割错乱**。任选一种安全方案并在项目固化：
   - 用 `WatchedFileHandler` + 交给系统 **logrotate** 切割（推荐，进程不负责切割）；或
   - 各 worker 写各自文件（`app.<pid>.log`）后合并；或
   - 统一走 `QueueHandler` → 单 listener 进程落盘。
   - **不要**让多个 worker 各自持有 `TimedRotatingFileHandler` 指向同一文件。
   - 切割策略须落实本文开头的留存约定：**按天切割、明文只留近 7 天、超 7 天压缩归档、压缩件保留 3 个月**（logrotate 用 `daily` + `compress`，并通过 `delaycompress` 等手段保证近 3 天不被压缩）。
2. **FastAPI async**：trace_id 用 `contextvars`（见第 2 节）。跨线程池（`run_in_executor`）、`asyncio.create_task` 时确认上下文已复制，否则 trace_id 在异步边界断裂。
3. **定时任务 / APScheduler**：每个 job 执行时生成 `trace_id` 并带 `job_id`，记录**起止两行**（开始 / 结束含 `duration_ms status`），便于回答"某任务几点跑了没、跑了多久、成没成"。job 使用互斥锁时，抢锁失败也要记一行。

---

## 10. 生命周期日志

用于回答"服务几点重启过""配置是不是变了""某后台任务在不在跑"。

- **启动**：记应用名、版本/git commit、环境（qa/product）、监听端口、**脱敏后的关键配置摘要**（DB host、Redis、外部服务开关——不含密钥）。
- **关闭**：记收到的信号、是否优雅退出。
- **依赖自检**：启动时探活 DB/Redis/关键三方，结果记一行（失败用 CRITICAL）。
- **scheduler**：启动时列出已注册的 job 及其调度表达式。

---

## 11. 前端（H5）错误与性能上报

卡顿和报错大量发生在前端。前端需把关键问题上报到后端，**复用同一套 `trace_id` 串联前后端**。

- **上报通道**：后端提供一个 `POST /log`（或 `/feedback/log`）接口接收前端上报，落到独立的 `frontend.log`（或并入 app.log 标 `source=frontend`）。
- **复用 trace_id**：前端发起的 API 请求带上后端返回的 `X-Trace-Id`；前端自身错误上报时，尽量带上**最近一次相关请求的 trace_id**，把前端异常和后端链路对上。
- **至少上报三类**：
  1. **JS 运行时错误**：`window.onerror` / `unhandledrejection`，带堆栈、页面 URL、UA。
  2. **白屏 / 资源加载失败**：关键资源加载失败、路由渲染异常。
  3. **性能**：首屏时间、慢接口（前端测得的 `duration_ms` 超阈值）。
- **节流去重**：前端上报必须节流/合并，避免错误风暴打爆接口；后端对该接口限流。
- 上报内容同样遵守[第 7 节脱敏](#7-敏感信息脱敏)。

> 前端上报通道的具体接口形态由各项目定，但 trace_id 串联与脱敏是本规范的底线要求（项目 `AI-*.md` 未另行约定时一律遵守）。

---

## 12. 标准字段字典

全应用统一使用下列 key（按需扩展，但同义不另起名）：

| key | 含义 | 示例 |
|---|---|---|
| `trace_id` | 链路 ID | `a1b2c3d4` |
| `user_id` | 用户 ID | `1001` |
| `job_id` | 定时任务/后台任务 ID | `daily_settle` |
| `method` / `path` / `status_code` | HTTP 请求 | `POST` `/order` `200` |
| `duration_ms` | 耗时（毫秒） | `83` |
| `slow` | 是否命中慢阈值 | `true` |
| `status` | 操作结果 | `ok` / `error` / `timeout` |
| `error_type` | 错误分类 | `timeout` / `conn` / `biz` / `integrity` / `upstream` / `unknown` |
| `provider` / `endpoint` | 三方服务与接口 | `openai` / `chat.completions` |
| `upstream_id` | 三方返回的 request-id | `req_abc` |
| `retries` / `timeout_ms` | 重试次数 / 超时阈值 | `1` / `3000` |
| `model` / `total_tokens` | LLM 专用 | `gpt-4o` / `1280` |
| `cache` | 缓存命中 | `hit` / `miss` |
| `truncated` / `len` | 内容被截断及原始长度 | `true` / `5230` |
| `source` | 日志来源（如前端上报） | `frontend` |

---

## 13. 排查工作流（怎么用）

这套规范的闭环——拿到线索后的标准动作：

1. **拿 trace_id**：用户报障让其提供 `X-Trace-Id`；或从 `error.log` 锁定一条 ERROR 取它的 `trace_id`。
2. **还原一次请求**：在 `logs/` 下用该 trace_id 横扫五个文件，按时间排好就是完整链路：
   ```bash
   grep -h "trace_id=<ID>" logs/*.log | sort
   ```
3. **查卡顿**：grep `slow=true`，或对 `duration_ms` 排序找最慢的环节，定位是 SQL、三方还是内部计算。
4. **查三方**：grep `provider=<x>` + `status=timeout|error`，结合 `upstream_id` 找三方对账。
5. **查报错面**：按 `error_type` 聚合，分清是业务、超时还是系统故障。
6. **衔接 qa 冒烟**：部署后 grep `error.log` 自部署时刻起的新增 ERROR——本规范的级别纪律（第 3 节）保证这一步不被业务噪音污染。

---

## 14. Agent 自查清单

实现/改动涉及日志时，逐条确认：

- [ ] 新增的关键路径有 `trace_id`，且子线程/异步/定时任务里没断。
- [ ] 外部调用（DB/Redis/LLM/三方）都记了 `duration_ms` 和 `status`。
- [ ] 慢阈值生效，命中时升 WARNING 并标 `slow=true`。
- [ ] ERROR 带完整堆栈（`exc_info=True`）和 `error_type`；超时标 `status=timeout`。
- [ ] 预期业务错误没有污染 error.log。
- [ ] 敏感字段已脱敏，没有密钥/token/验证码/完整卡号入日志。
- [ ] 大 payload 已截断并标 `truncated`。
- [ ] 多 worker 下日志切割方案安全，没有多进程争抢 `TimedRotatingFileHandler`。
- [ ] kv 字段名用[字段字典](#12-标准字段字典)里的标准 key，value 含空格已加引号。
- [ ] 改动若推翻本规范或项目 `AI-*.md` 中的日志约定，已同步更新文档。

# 应用规范

此规范记录应用的技术栈和目录规范，方便agent了解项目结构并遵守。

**此规范仅对python web项目有效**

## 应用目录结构

- 前后端分离 monorepo，一个仓库按应用类型分 2～6 个目录：
  - `frontend/` — H5 客户端（React）
  - `taro-miniprogram/` / `native-miniprogram/` — 小程序（按技术栈命名）
  - `backend/` — 服务端（Python）
  - 可选：`android/`、`ios/`
- 所有以 `AI-` 开头的 .md 文件（如 `AI-README.md`）是该项目供 LLM 参考的文档，**必须遵守其中的描述**。
- `node_modules/`、`.venv/`、`miniprogram_npm/` 等依赖/构建产物目录不入库；`package.json`、`requirements.txt` 依赖清单随代码维护最新。

### frontend（React H5）

- **技术栈**：React 18 + TypeScript + Vite 5 + React Router 6 + Zustand 4 + Axios + Less
- 运行 npm 命令前先确保依赖已安装（`npm install`）。
- 代码根目录 `src/`；配置文件 `vite.config.ts`、`tsconfig.json`；构建产物 `dist/`。

```
frontend/
├── src/
│   ├── main.tsx             # 入口：Provider 配置、路由挂载
│   ├── App.tsx              # 根组件：全局布局、错误边界
│   ├── components/          # ui/ 基础组件、layout/ 布局、business/ 业务组件
│   ├── pages/               # 页面组件（按路由分文件）
│   ├── hooks/               # 自定义 Hook
│   ├── stores/              # Zustand（按领域分文件）
│   ├── services/            # API 服务层（按后端模块分文件）
│   ├── router/              # 路由配置（index.tsx）
│   ├── utils/               # 工具函数
│   ├── types/               # TypeScript 类型
│   ├── assets/              # 静态资源
│   └── styles/              # 全局样式、Less 变量与混合
├── public/  index.html
├── vite.config.ts  tsconfig.json  package.json
└── deploy.sh
```

- 关键约定：
  - 组件 PascalCase，文件名与组件名一致；样式用 **CSS Modules + Less**，组件样式 `ComponentName.module.less` 与组件同目录。
  - 路由集中 `router/index.tsx`（`createBrowserRouter`），权限守卫 + `React.lazy` 懒加载 + 404 页。
  - 全局样式与变量放 `styles/`（`global.less`、`variables.less`、`mixins.less`）。
  - API 用统一 Axios 实例（baseURL、timeout、请求/响应拦截器统一处理 token 与错误）。
  - 构建 `npm run build`；部署脚本模板见 [templates/deploy-h5.sh](templates/deploy-h5.sh)（server.md H5 规范）。

### taro-miniprogram（Taro 小程序）

- **技术栈**：Taro 3 + React 18 + TypeScript + Less
- 运行 npm 命令前先确保依赖已安装（`npm install`）。
- 代码根目录 `src/`；配置 `config/index.ts`（分环境 `dev.ts` / `prod.ts`）、`tsconfig.json`；构建产物 `dist/`（按平台，如 `dist/weapp/`）。

```
taro-miniprogram/
├── src/
│   ├── app.tsx              # 应用入口
│   ├── app.config.ts        # 全局配置（pages、tabBar、subPackages）
│   ├── app.less             # 全局样式
│   ├── components/          # ui/ 基础组件、layout/ 布局、business/ 业务组件
│   ├── pages/               # 每页：index.tsx + index.less + index.config.ts（页面级配置）
│   ├── hooks/  stores/  services/  utils/  types/  assets/
├── config/                  # index.ts / dev.ts / prod.ts
├── package.json  tsconfig.json
└── deploy.sh
```

- 关键约定：
  - 组件 PascalCase；样式 Less，组件样式 `ComponentName.less` 与组件同目录；尺寸用 rpx。
  - 路由 / TabBar / 分包统一声明在 `app.config.ts`；页面配置用 `[page].config.ts` 覆盖全局。
  - API 用 `Taro.request`（不用 Axios）；状态用 Zustand，持久化在小程序端用 `Taro.setStorageSync`。
  - 登录用 `Taro.login` 取 code 交后端换 session_key/openid；支付用 `Taro.requestPayment`。
  - 构建 `npm run build:weapp`（H5 形态 `npm run build:h5`）；上传发布用微信开发者工具或项目 `deploy.sh`。

### native-miniprogram（原生小程序）

- **技术栈**：微信小程序原生框架 + JavaScript + WXSS
- 代码根目录 `miniprogram/`；配置 `project.config.json`、`miniprogram/app.json`；无单独构建目录。
- npm 依赖构建进 `miniprogram_npm/`（需在 `project.config.json` 开启 `packNpmRelationList`）。

```
native-miniprogram/
├── miniprogram/
│   ├── app.js  app.json  app.wxss   # 入口与全局配置（pages、tabBar、subPackages）
│   ├── components/          # ui/ 基础组件、layout/ 布局、business/ 业务组件，每组件 4 件套
│   ├── pages/               # 每页 4 件套：js / wxml / wxss / json
│   ├── utils/  services/  stores/  assets/
├── miniprogram_npm/
├── project.config.json  package.json
└── deploy.sh
```

- 关键约定：
  - 组件 kebab-case，每组件 4 件套（js / wxml / wxss / json），`component.json` 设 `"styleIsolation": "isolated"`。
  - 样式 WXSS，尺寸用 rpx；路由 / TabBar / 分包在 `app.json` 声明。
  - API 用 `wx.request`。
  - 登录用 `wx.login` 取 code 交后端换 session_key/openid；支付用 `wx.requestPayment`。

### backend

- Python 3.14
- 使用`uv`管理虚拟环境，使用`.venv/`目录存放虚拟环境
- 在 backend 下运行 python 命令前先 `source .venv/bin/activate`。
- `requirements.txt` 是 pip 依赖清单，随代码维护最新。
- 代码根目录 `app/`；配置文件 `config.toml`。
- 日志文件位于 `logs/`，应用须按此分类与格式配置：
  - `app.log` 所有日志；`sql.log` ORM 层 SQL；`request.log` 请求日志；`llm.log` LLM 交互（内容、应答、token 量）；`error.log` 错误日志。
  - 一行格式：`%(asctime)s [%(threadName)s] %(levelname)s [%(module)s:%(lineno)d]: %(message)s`
  - 按天拆分；留存策略（明文与压缩天数）以 [logging.md](logging.md) 为准。
  - **怎么写可排查的日志**（trace_id 链路、耗时与慢日志、三方交互、异常与超时、脱敏、多进程/异步/定时任务、噪音控制、前端错误上报）见 [logging.md](logging.md)，记录日志时必须遵守。

## 接口契约（OpenAPI）

- 每个 backend 维护 `backend/openapi.json` 作为接口契约的**唯一真源**，了解接口的入参出参时优先读它，而不是翻源码。
- **新增或修改接口后，必须重新导出 `openapi.json` 并随代码一同提交**。
  - FastAPI 应用：从 `app.openapi()` 导出（如 `python -c "import json; from app import main; print(json.dumps(main.app.openapi(), ensure_ascii=False))" > openapi.json`，以项目实际入口为准）。
- 写接口时必须填写 summary/description 与请求/响应模型，保证导出的 spec 可读——spec 的质量就是 agent 理解接口的质量。

## FastAPI 应用目录结构

技术栈：Python 3 + FastAPI + SQLAlchemy + aiomysql + MySQL 8.0 + Pydantic v2

```
The-fastApi-app/
  ├── app/                      # 应用主包（FastAPI 实例也在包内）
  │   ├── main.py               # 应用入口：创建 FastAPI app、注册中间件/异常处理器/路由、/ping 健康检查
  │   ├── __main__.py           # 可选：python -m app 起服务
  │   ├── config.py             # Config 类：用 toml 库读 config.toml，属性式访问，模块级单例 config
  │   ├── database.py           # 异步 engine、session factory、Base、init_db()、get_db 依赖
  │   ├── models/               # SQLAlchemy ORM（按领域分文件，新模型必须在 __init__.py 导出）
  │   ├── routers/              # FastAPI 路由（一域一文件），__init__.py 中统一注册到 api_router
  │   ├── schemas/              # Pydantic v2 请求/响应模型，response.py 提供统一 Response[T] 包装和 resp 单例
  │   └── utils/
  │       ├── deps.py           # 依赖注入（get_current_user 等，唯一允许 raise HTTPException 的地方）
  │       ├── security.py       # JWT / 密码
  │       └── exceptions.py, logger.py 等按需扩展
  ├── config.toml               # 实际配置（含密钥，不入库）；config.toml.example 为模板
  ├── requirements.txt          # pin 版本的依赖清单；工具链配置（ruff/mypy）在 pyproject.toml
  ├── .gitea/workflows/         # CI（见 [ci.md](ci.md)）
  ├── deploy.sh                 # SSH 部署脚本：./deploy.sh qa|product [init]
  └── tests/                    # pytest 测试
```

**入口约定**：FastAPI app 实例声明在 `app/main.py`，启动用 `uvicorn app.main:app`（生产 `gunicorn -c gunicorn.conf.py app.main:app worker_class=uvicorn.workers.UvicornWorker`）。

## 多应用共用域名的登录态隔离

### 背景

`h5.example.com/<app>`（QA：`h5.qa.example.com/<app>`）为多个 H5 应用共用域名，仅作静态托管。登录态 cookie 由后端在 `api.example.com`（多后端按 path 共用此域）下发，**不落在 h5 域**。

### 隔离要求

凡使用 cookie 下发登录态（Starlette `SessionMiddleware`）且部署在共用 `api.example.com` 的后端，**必须做登录态隔离**，否则多个后端下发的同名 cookie（如框架默认 `session`）会因「同名 + 同域 + `Path=/`」互相覆盖，导致用户切换应用时掉登录或串号。

### 隔离方案

Cookie 名带应用前缀，限定 Cookie 的 Path 为本应用路径。
Starlette：`SessionMiddleware(cookie_name='<app>_session', path='/<app>')`  

### 禁止组合

> **禁止**「框架默认 cookie 名 `session` + 默认 `Path=/` + 共用 `api.example.com`」——这是多应用串号的根因。

### 新应用推荐方案

- 使用 **JWT 放响应体 + 前端 localStorage/小程序 Storage 自存 + `Authorization: Bearer` 头**，天然规避 cookie 域冲突。

### Nginx 侧注意事项

- Nginx **不做** cookie 的 path/domain 改写（如 `proxy_cookie_path` 等）。
- 登录态隔离责任在**后端应用代码**，不依赖反代改写。

### CORS 与 Cookie 的独立性

- CORS 跨域判定只看 origin（scheme+host+port），**不看 path**。
- 给 cookie 加 Path **不需要**修改 CORS 配置。
- `Access-Control-Allow-Origin` 永远为 `https://h5(.qa).example.com`（不含 path）。
- **带凭证的跨源请求**（`withCredentials` / `credentials:'include'`）必须满足：
  - 后端返回 `Access-Control-Allow-Credentials: true`
  - `Access-Control-Allow-Origin` **必须精确回显 Origin，禁止 `*`**（浏览器对带凭证的跨源请求会直接拒绝 `*`）。
- 各共用 `api.example.com` 的后端需各自正确配置 CORS，不因 cookie path 隔离而省略。


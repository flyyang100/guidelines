# guidelines

公司统一的开发约定，供团队成员和 LLM coding agent（Claude Code、opencode、Cursor、Codex 等）共同遵循。

约定内容见 [GUIDELINES.md](GUIDELINES.md)（入口索引），具体规范分布在 `agent.md`、`git.md`、`app.md`、`server.md`、`logging.md`、`writing.md`，文档模板在 `templates/`。

## 如何接入/更新你的项目

在你的业务项目里打开你的 AI coding agent（Claude Code / opencode / Cursor 等），把下面这句话发给它：

```
请把 git@git.example.com:dev/guidelines.git clone 到临时目录，读取其中的 INSTALL.md，然后按指令把开发约定接入当前项目。
```

如果要更新，重新把上面的话发给你的agent。

## 项目专属约定

项目自身的特殊约定写在项目内以 `AI-` 开头的 `.md` 文件中（见 app.md 说明），优先级高于本通用约定。通用约定由本仓库统一维护，不要在各项目里直接改动；`.guidelines/` 不入版本控制，更新方式见上一节。

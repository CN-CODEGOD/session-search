---
name: session-search
description: "根据用户关键词扫描各个 session 内容，用 dre (llama3.1-8B) 快速压缩成 gist，再语义搜索匹配结果。用于跨会话搜索历史对话、找之前讨论过的内容。"
---

# Session Search — 跨会话语义搜索

根据用户关键词，扫描 session 历史 → dre 压缩 gist → 语义搜索 → 返回匹配结果。

## 架构

```
sessions_list → sessions_history(每个session) → summarize.sh(gist压缩) → cache → search_gists.sh(语义搜索)
```

- **压缩模型**: dre (llama3.1-8B, Cloudflare Workers, 免费, ~1s)
- **缓存**: `scripts/cache/` 目录，md5(sessionKey) 命名，已有则跳过
- **索引**: `scripts/cache/index.json` 记录 sessionKey → cacheFile 映射

## 脚本

| 脚本 | 用途 |
|------|------|
| `scripts/summarize.sh` | 单次压缩：文本 → gist |
| `scripts/batch_summarize.sh` | 批量压缩：JSONL输入，自动缓存，最多5个 |
| `scripts/search_gists.sh` | 语义搜索：在所有缓存 gist 中搜索关键词 |
| `scripts/cache/` | gist 缓存目录 |

## 执行流程

### Step 1: 获取会话列表

```
sessions_list(limit=20, excludeSubagents=true, includeDerivedTitles=true, archived="all")
```

提取每个 session 的 `key`, `sessionId`, `label`/`derivedTitle`。

### Step 2: 获取每个 session 的历史内容

对每个 session 调用：
```
sessions_history(sessionKey=<key>, limit=50)
```

从 messages 数组中提取 user/assistant 的文本内容，拼接为纯文本。

### Step 3: 压缩为 gist

准备 JSONL 输入文件 `/tmp/search_input.jsonl`，每行：
```json
{"sessionKey": "agent:main:...", "text": "提取的会话文本...", "label": "会话标题"}
```

执行批量压缩：
```bash
bash skills/session-search/scripts/batch_summarize.sh /tmp/search_input.jsonl /tmp/search_output.jsonl
```

每批次最多处理 5 个 session。如需更多，分批执行。已缓存的自动跳过。

### Step 4: 语义搜索

```bash
bash skills/session-search/scripts/search_gists.sh "用户搜索关键词" --top 5
```

输出匹配的 sessionKey、相关性评分和原因。

### Step 5: 展示结果

根据搜索结果，用 `sessions_history` 获取匹配 session 的相关上下文片段，向用户展示：
- 会话标题/时间
- 匹配原因
- 关键上下文片段

## 注意事项

- llama3.1-8B 上下文仅 8K，单 session 文本截断 6000 字符
- 首次扫描需要逐个压缩，之后命中缓存秒级完成
- 搜索本身也走 dre，返回 JSON 格式的匹配结果
- 缓存不自动过期；如需刷新，删除 `scripts/cache/` 下对应文件

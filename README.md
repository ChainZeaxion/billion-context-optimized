# billion-context-optimized

`billion-context` 的**优化增强版**，以单文件二进制形式分发（免 Node 运行时）。

上游项目：https://github.com/ranxianglei/billion-context （作者 ranxianglei）

本仓库**只做优化与修复，不改动上游核心**。所有改动均为针对生产环境实测发现问题的定向补丁。

---

## 相比上游，本版本修复 / 优化了什么

### 1. 子代理并发解锁（A+B）
- **问题**：多个子代理（subagent）与主会话被同一把 per-session 锁串行化，导致子代理排队、一个跑完下一个才开始。
- **修复**：
  - **A**：把流式转发（forward）移出 session 锁，同 session 的请求转发也能重叠进行。
  - **B**：识别子代理请求并拆分为独立 session（依据 system 提示中的子代理标记），使其天然并行。
  - A、B **叠加生效**：子代理同时享受两者；普通同 session 请求享受 A。单条命中即可解锁并发。

### 2. 超窗分段救援（salvage overflow）防御机制
- **问题**：当上下文一次性超过引擎窗口（例如长会话累积、大批量注入）时，常规压缩救不动，请求直接失败，整条链路白等数百秒。
- **修复**：
  - 新增**分段救援**：把超限内容切成约「min(压缩上限, 引擎窗口) / 3」大小的超级块，逐块压缩，直到压回安全线。段数随超限量线性可控（7× 窗口约 30 段）。
  - **优雅化**：相邻小块合并成大超级块再压缩（首版逐块只出 1 段导致段数爆炸 189 段；优化后 3× 仅 11 段、7× 约 30 段），且压得更彻底。
  - **进度式反馈**：救援期间**持续向前端流式发进度**（每段压缩后 + 每 2 秒一次心跳 ping），前端不再长时间无反馈、链路保持健康。
  - 触发点：预检（preflight）压缩救不动时，或后端返回 400 超窗时（每 session 限 1 次重试，防死循环）。
  - 压测（真实 token 口径）：1×、3×（714K）、7×（1.6M）全部成功救援回安全线。

### 3. 工具参数实时流（Write / Edit passthrough）
- **问题**：`Write` / `Edit` 等大参数工具的 `input_json` 参数被缓冲到流末尾一次性下发，前端看不到参数实时滚动。
- **修复**：白名单工具（默认 `Write,Edit`，可用 `BILI_PASSTHROUGH_TOOLS` 增删）的 `input_json_delta` 逐条实时透传，前端看到参数实时流入。

### 4. thinking 处理开关
- 新增 `BILI_DROP_THINKING` 开关：可选在出站方向剥离 thinking 块（并可暂存、按需经 decompress 取回），用于下游不消费 thinking 的场景，减小传输体积。

### 5. 前端标记截断
- `acp_status` / `compress` 等前端状态标记的冗长输出被截断（超长正文截断、失败结果保留全文），并落滚动单文件日志，避免刷屏。

### 6. 大文本分级挽救 / 硬性拒载
- **问题**：一次性读入超长文本文件时，要么整段撑爆上下文，要么被无差别压缩丢信息。
- **修复**：按后端窗口把文本分成**三档**处理——未超限直接归档；介于挽救线与拒载线之间走**两阶段分段摘要挽救**（先分块独立摘要、再跨段去重合并建关联），宁可多轮次也不丢上下文；超**硬性拒载线（默认 100 万字符）**才拒载并给出明确提示。阈值可用 `BILI_TEXT_SALVAGE_CHARS` / `BILI_TEXT_REJECT_CHARS` 覆盖。
- **附带修复**：压缩触发判定（nudge）的窗口占用比此前被压缩档误压小，导致频繁触发压缩；现已改回用真实后端窗口计算，压缩触发回归正常阈值。

### 7. 实时 Token 速度（TPS）面板
- **新增**：Web 概览页显示**近 5 分钟**的 token 速度——顶部为所有实时会话的 **output 速度合计**，下方逐会话列出 **output 速度 / prefill 速度 / 历史最佳 / 均值**（最多 30 个会话）。近 5 分钟无实时数据的会话显示历史最佳与均值；有数据则显示、5 分钟无数据自动隐藏，页面自动轮询刷新。
- **新增**：概览页显示**全部会话的累计 Token 用量**——输入 token / 其中缓存命中 / 输出 token / 请求次数 / 缓存命中率。

### 8. 其它
- 关闭自动更新（`ACP_AUTO_UPDATE=0`），避免上游自动升级覆盖本地补丁。
- 管理面板 `/__bili/` 放行内网私网段访问。

---

## 快速开始

**安装（自动选平台 + 校验）：**

```bash
curl -fsSL https://raw.githubusercontent.com/ChainZeaxion/billion-context-optimized/main/install.sh | bash
```

**手动安装：**

1. 从 [Releases](https://github.com/ChainZeaxion/billion-context-optimized/releases) 下载对应平台的二进制：
   - `bili-linux-x64`（Linux 64 位）
   - `bili-linux-arm64`（Linux ARM64）
   - `bili-macos-arm64`（macOS Apple Silicon）
   - `bili-windows-x64.exe`（Windows 64 位）
2. 校验：`sha256sum <文件>` 与 `SHA256SUMS.txt` 比对。
3. 赋予执行权限并运行：
   ```bash
   chmod +x bili-linux-x64
   ./bili-linux-x64 --port 8878 --host 0.0.0.0
   ```

**接入 agent：** 在任意 agent 的 base URL 前加上 `http://<host>:8878/bili/`。例如把
`http://192.168.10.43:8000` 改写成 `http://192.168.10.43:8878/bili/http://192.168.10.43:8000`。

常用环境变量：

| 变量 | 说明 | 默认 |
|---|---|---|
| `BILI_PASSTHROUGH_TOOLS` | passthrough 白名单 | `Write,Edit` |
| `BILI_DROP_THINKING` | `1` 出站剥离 thinking | `0` |
| `ACP_AUTO_UPDATE` | `0` 关自动更新 | `0` |

---

## 许可

**允许使用，禁止再改。** 详见 [`LICENSE`](LICENSE)。

一句话：你可以自由使用、分发本仓库的二进制构建；但**不建议**在本版本基础上做二次修改。如果你有自定义需求，请优先回到上游主线项目 [billion-context](https://github.com/ranxianglei/billion-context) 提交/跟进。本仓库更新节奏以维护者心情为准，欢迎使用，不保证响应 issue。

---

## 备注
- 本仓库只分发**二进制**，不含上游/本版的源码，也无需 Node.js。
- 二进制为混淆（minified）后的单文件可执行程序。

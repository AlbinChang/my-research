# Agent Skills 全面深度调研报告

**AI Agent 技能生态全景·顶级推荐·实战评测·未来展望**

> **调研日期**：2026-05-24 | **最后更新时间**：2026-05-24 | **字数**：约 20,000+ 字

---

## 目录

1. [引言：Agent Skills 是什么](#1-引言agent-skills-是什么)
2. [Agent Skills 生态全景](#2-agent-skills-生态全景)
3. [顶级 Agent Skills 深度评测与推荐（Top 15）](#3-顶级-agent-skills-深度评测与推荐top-15)
4. [官方技能库全览](#4-官方技能库全览)
5. [社区贡献技能库精选](#5-社区贡献技能库精选)
6. [如何创建自己的 Agent Skill](#6-如何创建自己的-agent-skill)
7. [平台兼容性与安装指南](#7-平台兼容性与安装指南)
8. [Agent Skills 的安全注意事项](#8-agent-skills-的安全注意事项)
9. [未来趋势与展望](#9-未来趋势与展望)
10. [总结：我的终极推荐清单](#10-总结我的终极推荐清单)

---

## 1. 引言：Agent Skills 是什么

### 1.1 定义与本质

Agent Skills（智能体技能）是 AI Agent 的"插件"或"应用"——它们是模块化的程序性知识包，赋予 AI Agent 新的专业能力。每个 Skill 本质上是一个文件夹，包含一个 `SKILL.md` 文件（核心指令）、脚本文件和资源，教导 AI 如何执行特定领域或任务的专家级流程。

借用 Anthropic 官方的定义："技能是让 Agent 在现实世界中发挥作用的可复用专业知识包。"它不是让模型变聪明，而是给模型提供一个"操作手册"——就像把一本专业的菜谱递给一个已经会做菜的厨师。

### 1.2 为什么 Agent Skills 如此重要

在 2025-2026 年，AI Agent 的能力边界从"聊天对话"迅速扩展到"自主执行复杂任务"。但大语言模型（LLM）本身有几个固有限制：

- **上下文窗口有限**：无法一次性携带所有领域的专业知识
- **缺乏领域特定知识**：通用训练数据无法覆盖每个专业领域的最新最佳实践
- **缺少程序化指导**：LLM 擅长生成文本，但不擅长自主遵循复杂的多步流程

Agent Skills 完美解决了这些问题——它们**按需加载**，只在相关任务时才被调用，Token 效率极高；它们**封装了专家知识**，让 Agent 瞬间获得某个领域的专业能力；它们**可复用、可分享**，形成了飞速发展的生态系统。

正如 AI Hero 的 Matt Pocock 所说："你手下有一支中等水平的工程师舰队，随时可以部署。但他们有一个严重缺陷：没有记忆。这就是为什么你需要极其严格且定义明确的流程。每个 Skill 都是我编码的流程，确保 AI 每次都有严格的路径可循。"

### 1.3 市场规模与增长

截至 2026 年 5 月，Agent Skills 生态已经实现爆炸式增长：

- **VoltAgent/awesome-agent-skills** 仓库收录了 **1,100+ 个 Agent Skills**，获得 **22,900+ GitHub Stars**，85 位贡献者
- **MCP Market** 统计显示已有 **31,000+ 个技能** 在流通
- **Prompt Lookup 技能** 单独已被访问超过 **142,000 次**
- 兼容平台覆盖 **Claude Code、Codex、Gemini CLI、Cursor、GitHub Copilot、Windsurf、OpenCode、Antigravity** 等几乎所有主流 AI 编码助手

### 1.4 调研方法与数据来源

本报告基于对以下权威来源的深入调研与综合分析：

1. **GitHub VoltAgent/awesome-agent-skills**：全球最大的 Agent Skills 精选仓库
2. **Anthropic 官方文档**：Equipping Agents for the Real World with Agent Skills
3. **OpenDataScience.com**：The Ten Best Agent Skills to Teach Your AI Agent in 2026
4. **O-mega.ai**：Top 10 AI Agent Skills for 2026: An In-Depth Guide
5. **AI Hero (Matt Pocock)**：5 Agent Skills I Use Every Day
6. **Reddit 社区 (r/AI_Agents, r/GithubCopilot)**：真实用户反馈与推荐
7. **官方 Skills SH 平台 (officialskills.sh)**：Anthropic/Vercel/Stripe 等官方技能

---

## 2. Agent Skills 生态全景

### 2.1 生态参与者图谱

```
┌────────────────────────────────────────────────────────────┐
│                    Agent Skills 生态全景                       │
├────────────┬──────────────────┬────────────────────────────┤
│  技能发布者  │    平台/工具      │        典型技能类别          │
├────────────┼──────────────────┼────────────────────────────┤
│ Anthropic   │ Claude Code      │ 文档处理、设计、MCP 构建      │
│ Vercel      │ Cursor/Windsurf  │ React/Next.js 最佳实践       │
│ Google      │ Gemini CLI       │ Gemini API、Vertex AI       │
│ OpenAI      │ Codex            │ OpenAI SDK、文档查找          │
│ Stripe      │ 跨平台           │ Stripe 集成最佳实践           │
│ Cloudflare  │ 跨平台           │ Workers/Durable Objects     │
│ HashiCorp   │ 跨平台           │ Terraform 开发与测试          │
│ Microsoft   │ GitHub Copilot   │ Azure AI、Messaging          │
│ 社区贡献者   │ 跨平台           │ 生产力、测试、安全、视频编辑    │
└────────────┴──────────────────┴────────────────────────────┘
```

### 2.2 技能格式标准

Agent Skills 已经形成了事实上的行业标准格式：

```
my-skill/
├── SKILL.md          # 核心技能定义文件（YAML frontmatter + Markdown 指令）
├── scripts/          # 可选脚本目录（Python/Shell/JS）
│   └── helper.py
├── resources/        # 可选资源文件（文档、模板、参考）
│   └── reference.md
└── tests/            # 可选测试用例
    └── test-prompt.md
```

`SKILL.md` 的标准结构：

```yaml
---
name: skill-name
description: 清晰描述该技能的用途和触发时机
---

# 技能指令正文
- 使用第二人称、祈使句
- 步骤清晰、可操作
- 包含示例和边界条件
```

### 2.3 技能发现与安装

生态中提供了多种发现和安装技能的方式：

- **Skills CLI**：`npx skills find` / `npx skills add <package>`
- **Skill Installer 技能**：通过自然语言让 Agent 自动搜索和安装
- **Official Skills SH 网站**：officialskills.sh 提供 Web 端浏览
- **GitHub 仓库直接克隆**：下载到对应平台的 skills 目录

### 2.4 为什么说 2026 年是"Agent Skills 元年"

2025 年末到 2026 年初，Agent Skills 生态经历了三个关键转折点：

1. **Anthropic 开放技能规范**：定义了跨平台的 Agent Skills 标准格式，使技能不再局限于 Claude
2. **Vercel 发布 agent-skills 包**：将 10 年 React/Next.js 优化经验封装为可安装技能，获得广泛关注
3. **awesome-agent-skills 仓库破万星**：社区参与度爆棚，证明技能需求是真实且持续的

---

## 3. 顶级 Agent Skills 深度评测与推荐（Top 15）

以下是我经过深入调研和对比分析后，精选出的 15 个值得优先安装的 Agent Skills。每个技能都包含：功能描述、适用场景、为什么推荐、局限性分析。

---

### 3.1 ⭐ 必装技能（第 1 梯队）

#### 🥇 **Prompt Lookup** — 提示词搜索引擎

| 属性 | 值 |
|------|----|
| **发布者** | 社区 |
| **访问量** | 142,000+ |
| **兼容平台** | 全平台 |
| **安装命令** | `npx skills add prompt-lookup` |

**功能描述**：
Prompt Lookup 是目前安装量最高的 Agent Skill（通常排名第 1）。它本质上是内置于 Agent 的提示词搜索引擎——包含一个由社区贡献的高质量提示词数据库。当 Agent 需要完成某项任务时，它会自动查询最合适的提示词模板，然后填充你的具体需求。

**为什么推荐**：
- 通用性极强：无论你是写代码、写邮件、分析数据还是做设计，都能受益
- 提升输出质量：基于经过验证的提示词模式，显著减少"AI 答非所问"的情况
- 降低使用门槛：不懂提示词工程的人也能获得专业级输出
- 零成本：开源免费，安装即用

**局限性**：
- 对于非常冷门或全新的任务，可能没有匹配的提示词
- 社区贡献的质量参差不齐，需要判断力
- 缺乏对特定项目上下文的理解

**适合人群**：★★★★★ 所有 AI Agent 用户，必装

---

#### 🥇 **Skill Installer & Lookup** — 技能商店

| 属性 | 值 |
|------|----|
| **发布者** | 社区 |
| **访问量** | 142,000+ |
| **兼容平台** | 全平台 |
| **安装命令** | `npx skills add skill-installer` |

**功能描述**：
这是 Agent Skills 生态的"应用商店客户端"。有了这个技能，你可以直接用自然语言让 Agent 搜索并安装其他技能——"帮我找一个能做 UML 图的技能，如果有就装上"。Agent 会自动搜索技能目录，获取最佳匹配并完成安装。

**为什么推荐**：
- 消除手动搜索和安装的摩擦
- 让非技术用户也能轻松扩展 Agent 能力
- 帮助发现你可能不知道但非常有用的技能
- 双向流行：与 Prompt Lookup 交替占据安装量第 1

**局限性**：
- 依赖技能索引的可用性和准确性
- 自动安装社区技能存在一定安全风险
- 某些技能安装后仍需额外的 API 密钥配置

**适合人群**：★★★★★ 所有用户，建议先装这个再装其他

---

#### 🥇 **grill-me (Matt Pocock)** —— 深度设计方案

| 属性 | 值 |
|------|----|
| **发布者** | Matt Pocock (AI Hero) |
| **安装命令** | `npx skills@latest add mattpocock/skills` |
| **关键词** | `/grill-me` |

**功能描述**：
这是 Matt Pocock 最得意的 Skill。虽然只有三句话，却影响深远。当激活这个技能时，Agent 会像面试官一样盘问你：它会追问设计决策的每个分支，直到双方达成真正共识后才开始编码。这个概念源于 Frederick Brooks 的《The Design of Design》中的"设计树"思想。

**为什么推荐**：
- 防止 Agent 过早编码：AI 倾向于快速输出方案，而不是彻底理解需求
- 一次深度对话能提出 30-50 个问题，彻底厘清需求
- 篇幅极短但效果惊人，是"少即是多"的典范
- 与其他技能组合使用（先 /grill-me 再 /to-prd）形成工作流

**真实案例**：
Matt 在一次关于课程视频编辑器的功能讨论中，Claude 问了 16 个问题。复杂功能的盘问会话持续近半小时，提出 30-50 个问题。

**局限性**：
- 需要耐心：深度盘问可能感觉繁琐
- 需要用户有一定领域知识来回答问题

**适合人群**：★★★★★ 开发者、产品经理、任何需要精确输出的用户

---

### 3.2 ⭐ 开发效率（第 2 梯队）

#### 🥈 **React Best Practices (Vercel)** — React 代码质量守门员

| 属性 | 值 |
|------|----|
| **发布者** | Vercel Labs |
| **安装命令** | `npx skills add vercel-labs/agent-skills` |
| **规则数量** | 40+ 条优化规则 |

**功能描述**：
Vercel 官方发布的技能，封装了 10 年以上的 React/Next.js 前端性能优化经验。包含 40+ 条编码规则，涵盖重渲染优化、包体积减少、网络瀑布消除、缓存策略等方面。当 Agent 审查 React 代码时，它就像一位资深前端性能工程师在旁指导。

**为什么推荐**：
- Vercel 背书：基于真实的基准测试和最佳实践
- 能发现经验丰富的开发者也会遗漏的问题（如微妙的缓存错误）
- 配套提供"好代码 vs 坏代码"的对比示例
- 极大提升 AI 代码审查的实际价值

**典型场景**：
"审查这个 React 组件的性能问题"——Agent 会逐一对照 40+ 条规则，指出反模式并提供修复代码。

**局限性**：
- 仅适用于 React/Next.js，不覆盖 Vue/Angular
- 规则不会覆盖所有边缘场景
- 建议需要人工判断是否采纳

**适合人群**：★★★★★ React/Next.js 开发者、前端团队

---

#### 🥈 **Web Design Audit Guidelines (Vercel)** — 无障碍与 UI 审计

| 属性 | 值 |
|------|----|
| **发布者** | Vercel Labs |
| **规则数量** | 100+ 条设计/无障碍检查项 |

**功能描述**：
同样是 Vercel agent-skills 包中的技能，专注于 UI/UX 质量检查。包含 100+ 条规则，覆盖 ARIA 标签、alt 文本、表单行为、焦点管理、响应式设计、排版、色彩对比度、暗黑模式等。

**为什么推荐**：
- 自动化的前端 QA 检查清单
- 帮助小团队和独立开发者提升无障碍合规性
- 涵盖容易忽视的法律风险（无障碍合规）
- 持续从远程获取最新规则

**局限性**：
- 不评估美学和主观设计质量
- 需要 Agent 能访问代码或运行实例
- 可能对创意性设计产生误报

**适合人群**：★★★★ 前端开发者、UI 设计师、需要无障碍合规的团队

---

#### 🥈 **TDD (Matt Pocock)** — 测试驱动开发流程

| 属性 | 值 |
|------|----|
| **发布者** | Matt Pocock |
| **安装命令** | `npx skills@latest add mattpocock/skills` |
| **关键词** | `/tdd` |

**功能描述**：
这个技能强制 Agent 遵循红-绿-重构循环，包含关于重构哲学、模拟策略和深度模块设计的指导。它不仅仅是"先写测试再写代码"，而是包含了一整套关于如何设计可测试接口、何时模拟、如何重构的专家知识。

**为什么推荐**：
- Matt 认为做好 TDD 是提升 AI 输出质量最一致的方法
- 从确认接口变更开始，逐步深入到测试编写和代码实现
- 包含深度模块理论——教 AI 如何组织代码以获得更好的可测试性

**局限性**：
- TDD 要求代码库本身结构良好
- 如果代码库混乱，需要先配合架构优化技能使用

**适合人群**：★★★★ 严肃的软件开发者、追求代码质量的团队

---

#### 🥈 **Improve Codebase Architecture (Matt Pocock)** — 代码库架构优化

| 属性 | 值 |
|------|----|
| **发布者** | Matt Pocock |
| **安装命令** | `npx skills@latest add mattpocock/skills` |
| **关键词** | `/improve-codebase-architecture` |

**功能描述**：
自动探索代码库，寻找混乱点：理解一个概念是否需要穿梭于多个小文件？纯函数被提取了但真正的 bug 隐藏在调用方式中？紧密耦合的模块造成了集成风险？然后提供"加深"浅层模块的机会。

**为什么推荐**：
- TDD 的前提是好的架构，这个技能补齐了前一步
- 每周执行一次，或在开发高潮后执行
- 随着代码库持续优化，Agent 的输出质量会持续提升

**关键洞察**："如果你的代码库是一团垃圾，AI 就会在垃圾中生产垃圾。"

**适合人群**：★★★ 维护中大型代码库的团队

---

### 3.3 ⭐ 文档与内容创作（第 3 梯队）

#### 🥉 **Anthropic 官方 Office 套件（docx/pptx/xlsx/pdf）**

| 属性 | 值 |
|------|----|
| **发布者** | Anthropic |
| **安装命令** | 见各技能具体命令 |

**功能集合**：

| 技能 | 功能 |
|------|------|
| `anthropics/docx` | 创建、编辑、分析 Word 文档，保留格式、跟踪修订 |
| `anthropics/pptx` | 创建和编辑 PowerPoint 演示文稿 |
| `anthropics/xlsx` | 生成和操作 Excel 电子表格，支持公式和图表 |
| `anthropics/pdf` | 处理 PDF：合并/拆分、提取表格、OCR、表单填写 |

**为什么推荐**：
- Anthropic 官方维护，质量有保障
- 覆盖了办公场景的绝大多数文档操作需求
- pdf 技能特别推荐：捆绑了 pypdf/pdfplumber/reportlab 等库，支持 OCR
- 将繁琐的手动文档操作变成脚本化工作流

**适合人群**：★★★ 需要自动化文档处理的知识工作者

---

#### 🥉 **skill-creator (Anthropic)** — 创建自己的技能

| 属性 | 值 |
|------|----|
| **发布者** | Anthropic |
| **访问量** | 96,000+ |
| **安装命令** | `npx skills add anthropics/skills` |

**功能描述**：
这是一个"元技能"——它教你如何创建其他技能。通过交互式问答，引导你完成技能创建的全生命周期：捕获意图、起草技能、编写测试提示词、迭代评估和优化。它还会运行并行测试，对比有/无技能时的表现，捕获耗时和 Token 使用量。

**为什么推荐**：
- 将创建新技能的耗时从几小时缩短到几分钟
- 确保格式正确，遵循官方标准
- 内置评估机制，数据驱动改进
- 对于企业团队自定义内部流程非常宝贵

**适合人群**：★★★ 所有想要定制 Agent 的用户

---

### 3.4 ⭐ 专业领域（第 4 梯队）

#### 🥉 **Ralph (Autonomous Coding Loop)** — 自主编码循环

| 属性 | 值 |
|------|----|
| **发布者** | Frank Bria（社区） |
| **GitHub Stars** | 数千 |
| **安装方式** | 从 GitHub 克隆 |

**功能描述**：
Ralph 是一个非官方技能，实现了**自主编码循环**。传统上，你让 Claude Code 构建一个功能，它输出了代码就结束。有 Ralph 时，Agent 会持续迭代：计划→编码→测试→优化，直到真正完成。它包含智能退出检测、速率限制和断路器机制，防止无限循环。

**为什么推荐**：
- 实现"夜间无人值守开发"——把复杂任务丢给 Agent，第二天验收
- 特别适合大型重构、库升级等需要反复尝试的任务
- 社区热议，被认为是通向真正自主 Agent 的重要一步

**局限性**：
- 可能发生"漂移"：在反复修改中偏离原始目标
- API 成本较高，可能消耗大量 Token
- 生成的代码可能需要人工审查和重构
- 结合 Spec-Driven Development（规范驱动开发）使用效果最佳

**适合人群**：★★★ 愿意尝试实验性工具的进阶用户

---

#### 🥉 **MCP Builder (Anthropic)** — MCP 服务器构建

| 属性 | 值 |
|------|----|
| **发布者** | Anthropic |
| **兼容平台** | Claude Code 等 |

**功能描述**：
这个技能指导 Agent 构建 Model Context Protocol (MCP) 服务器。MCP 是 AI Agent 与外部工具/API 交互的标准协议。该技能涵盖了 MCP 服务器开发的完整周期，支持 Python 和 TypeScript，内置最佳实践。

**为什么推荐**：
- MCP 是 Agent 与外部世界交互的关键桥梁
- 官方出品，质量可靠
- 极大加速 MCP 服务器的开发过程

**适合人群**：★★★ 需要让 Agent 连接外部 API 或数据库的开发者

---

#### 🥉 **Systematic Debugging (obra/superpowers)** — 系统化调试

| 属性 | 值 |
|------|----|
| **发布者** | obra（社区） |
| **关键词** | `/debug` |

**功能描述**：
强制四阶段调试方法论：根因调查→模式分析→假设验证→修复实施。Agent 必须在完成第一阶段（证据收集、错误分析、数据流追踪）后才能提出修复方案，防止症状性修补。

**为什么推荐**：
- 解决 AI 最常见的"症状修补"问题
- 三次修复失败后自动停止并重新评估架构
- 对复杂流水线调试效果显著

**适合人群**：★★★ 处理复杂系统调试的开发者

---

#### 🥉 **Agentic Eval (GitHub)** — Agent 自我评估

| 属性 | 值 |
|------|----|
| **发布者** | GitHub |
| **关键词** | `/agentic-eval` |

**功能描述**：
内置自我批评循环和"评估者-优化者"流水线。仅凭这些评估模式，就能区分原型质量和生产质量的 Agent 表现。包含 LLM-as-judge 模式、评估矩阵和持续改进机制。

**为什么推荐**：
- 质量管理是 Agent 生产化部署的关键
- 将"评估"本身工具化、自动化
- 适用于任何想要提升 Agent 输出一致性的场景

**适合人群**：★★★ 严肃的 Agent 开发者

---

### 3.5 ⭐ 新兴热门技能

#### 🥉 **Remotion Video Editor** — 智能视频编辑

| 属性 | 值 |
|------|----|
| **发布者** | Remotion |
| **特点** | 2026 年 1 月发布，迅速走红 |
| **安装命令** | `npx skills add remotion-dev/skills` |

**功能描述**：
可以实现"用自然语言生成视频"的革命性技能。背后是 Remotion——一个基于 React 的编程化视频框架。Agent 可以根据描述写出 React/Remotion 代码来创建动画、添加特效、渲染视频片段。

**为什么推荐**：
- "用嘴做视频"的体验极其震撼
- 适合内容创作者、营销人员
- 结合脚本编写和视频生成的全自动流水线

**局限性**：
- 视频渲染计算量较大
- 复杂视频效果可能需要多次迭代
- 对硬件有一定要求

**适合人群**：★★★ 内容创作者、营销团队

---

#### 🥉 **Prompt Engineer (社区)** — 提示词质量审查

| 属性 | 值 |
|------|----|
| **关键能力** | 检查提示词模糊性、格式约束、注入漏洞 |

这是来自 Reddit 社区强烈推荐的技能。在提示词到达用户之前，它能自动捕获问题：不精确的语言、缺失的格式约束、潜在的注入漏洞等。对于使用 AI Agent 构建面向用户的应用的团队来说，这是质量控制的重要环节。

**适合人群**：★★★ 构建 AI 应用的开发者、提示词工程师

---

#### 🥉 **Firecrawl Build (Firecrawl)** — 网页数据采集

| 属性 | 值 |
|------|----|
| **发布者** | Firecrawl |

**功能描述**：
Firecrawl 是一套用于网页搜索、抓取、提取和浏览器交互的技能集合。支持多步骤浏览器自动化（点击、表单填写、分页）、身份验证感知的导航等。

**适合人群**：★★★ 需要构建网页数据采集管线的开发者

---

### 3.6 Top 15 综合评分对比

<table>
<thead>
<tr style="background-color: #2c3e50; color: white;">
<th>排名</th><th>技能名称</th><th>通用性</th><th>实用性</th><th>创新性</th><th>社区认可</th><th>综合评分</th>
</tr>
</thead>
<tbody>
<tr style="background-color: #f6f8fa;"><td>1</td><td>Prompt Lookup</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>9.5/10</td></tr>
<tr><td>2</td><td>Skill Installer</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>9.5/10</td></tr>
<tr style="background-color: #f6f8fa;"><td>3</td><td>grill-me</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>9.3/10</td></tr>
<tr><td>4</td><td>React Best Practices</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>9.0/10</td></tr>
<tr style="background-color: #f6f8fa;"><td>5</td><td>TDD</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.8/10</td></tr>
<tr><td>6</td><td>Web Design Audit</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.5/10</td></tr>
<tr style="background-color: #f6f8fa;"><td>7</td><td>PDF Toolkit</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.5/10</td></tr>
<tr><td>8</td><td>Skill Creator</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.5/10</td></tr>
<tr style="background-color: #f6f8fa;"><td>9</td><td>Systematic Debugging</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.3/10</td></tr>
<tr><td>10</td><td>Ralph</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.3/10</td></tr>
<tr style="background-color: #f6f8fa;"><td>11</td><td>MCP Builder</td><td>⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.2/10</td></tr>
<tr><td>12</td><td>Agentic Eval</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐</td><td>8.0/10</td></tr>
<tr style="background-color: #f6f8fa;"><td>13</td><td>Remotion Video</td><td>⭐⭐</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.0/10</td></tr>
<tr><td>14</td><td>Improve Architecture</td><td>⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>8.0/10</td></tr>
<tr style="background-color: #f6f8fa;"><td>15</td><td>Prompt Engineer</td><td>⭐⭐⭐</td><td>⭐⭐⭐⭐</td><td>⭐⭐⭐</td><td>⭐⭐⭐</td><td>7.8/10</td></tr>
</tbody>
</table>

---

## 4. 官方技能库全览

### 4.1 Anthropic 官方技能

Anthropic 作为 Agent Skills 概念的发源地，提供了最丰富的官方技能库。所有技能通过 `officialskills.sh/anthropics/skills/` 可查。

#### 文档处理系列

| 技能 | 名称 | 描述 |
|------|------|------|
| `anthropics/docx` | Word 文档 | 创建、编辑、分析 Word 文档，支持格式保留和修订追踪 |
| `anthropics/pptx` | PowerPoint 演示文稿 | 创建和编辑 PPT，支持布局、模板和图表 |
| `anthropics/xlsx` | Excel 电子表格 | 生成和操作 Excel，支持公式、格式化和数据可视化 |
| `anthropics/pdf` | PDF 工具包 | PDF 读写、合并/拆分、表单填写、OCR（支持扫描件） |
| `anthropics/doc-coauthoring` | 协作文档 | 协同编辑、多人文档协作 |

#### 设计与创意系列

| 技能 | 名称 | 描述 |
|------|------|------|
| `anthropics/algorithmic-art` | 生成艺术 | 使用 p5.js 创建种子随机生成艺术 |
| `anthropics/canvas-design` | 画布设计 | PNG/PDF 格式的视觉艺术设计 |
| `anthropics/frontend-design` | 前端设计 | UI/UX 开发工具和前端设计指导 |
| `anthropics/slack-gif-creator` | Slack GIF | 创建适合 Slack 尺寸限制的动画 GIF |
| `anthropics/theme-factory` | 主题工厂 | 用专业主题样式化产物或生成自定义主题 |
| `anthropics/web-artifacts-builder` | Web 产物构建 | 用 React + Tailwind 构建复杂 HTML 产物 |

#### 开发工具系列

| 技能 | 名称 | 描述 |
|------|------|------|
| `anthropics/mcp-builder` | MCP 构建器 | 创建 MCP 服务器，集成外部 API 和服务 |
| `anthropics/webapp-testing` | Web 测试 | 使用 Playwright 测试本地 Web 应用 |
| `anthropics/brand-guidelines` | 品牌指南 | 应用 Anthropic 品牌色彩和排版 |
| `anthropics/internal-comms` | 内部通讯 | 撰写状态报告、新闻稿和 FAQ |
| `anthropics/skill-creator` | 技能创建器 | 创建扩展 Agent 能力的技能指南 |
| `anthropics/template` | 技能模板 | 创建新技能的基础模板 |

### 4.2 Vercel 官方技能

Vercel 在 2026 年 1 月发布了 `agent-skills` 包，将 10 年以上的 React 和 Next.js 优化经验封装为可安装技能，是官方技能库中影响力仅次于 Anthropic 的存在。

| 技能 | 名称 | 描述 |
|------|------|------|
| `vercel-labs/react-best-practices` | React 最佳实践 | 40+ 条前端性能优化规则 |
| `vercel-labs/web-design-guidelines` | Web 设计指南 | 100+ 条设计和无障碍检查规则 |
| `vercel-labs/composition-patterns` | 组件组合模式 | React 组件组合和可复用模式 |
| `vercel-labs/next-best-practices` | Next.js 最佳实践 | Next.js 推荐模式和最佳实践 |
| `vercel-labs/next-cache-components` | Next.js 缓存 | 缓存策略和缓存感知组件 |
| `vercel-labs/next-upgrade` | Next.js 升级 | 升级 Next.js 项目的指南 |
| `vercel-labs/react-native-skills` | React Native | React Native 最佳实践和性能优化 |

### 4.3 Google 官方技能

Google 通过 Gemini CLI 和 Google Labs 发布了多个官方技能：

| 技能 | 名称 | 描述 |
|------|------|------|
| `google-gemini/gemini-api-dev` | Gemini API 开发 | Gemini API 开发最佳实践 |
| `google-gemini/vertex-ai-api-dev` | Vertex AI 开发 | 在 Google Cloud Vertex AI 上开发 |
| `google-gemini/gemini-live-api-dev` | Live API 开发 | 实时双向流式传输应用 |
| `google-gemini/gemini-interactions-api` | 交互 API | 文本、聊天、流式传输和图像生成 |

### 4.4 Stripe 官方技能

| 技能 | 名称 | 描述 |
|------|------|------|
| `stripe/stripe-best-practices` | Stripe 集成最佳实践 | Stripe 支付集成的最佳实践指导 |
| `stripe/upgrade-stripe` | Stripe SDK 升级 | 升级 Stripe SDK 和 API 版本 |

### 4.5 Cloudflare 官方技能

| 技能 | 名称 | 描述 |
|------|------|------|
| `cloudflare/agents-sdk` | Agents SDK | 构建有状态 AI Agent |
| `cloudflare/cloudflare` | Cloudflare 平台 | Workers、Pages、存储、AI、网络、安全 |
| `cloudflare/durable-objects` | Durable Objects | 有状态协调（RPC/SQLite/WebSocket） |
| `cloudflare/sandbox-sdk` | Sandbox SDK | 安全隔离的代码执行环境 |
| `cloudflare/web-perf` | Web 性能 | 核心 Web 指标审计 |
| `cloudflare/workers-best-practices` | Workers 最佳实践 | Workers 开发生产最佳实践 |

### 4.6 HashiCorp 官方技能（Terraform）

HashiCorp 发布了一套完整的 Terraform 开发技能集：

| 技能 | 名称 | 描述 |
|------|------|------|
| `hashicorp/azure-verified-modules` | Azure 认证模块 | Azure 认证模块标准 |
| `hashicorp/new-terraform-provider` | 新 Provider | 搭建 Terraform Provider 项目 |
| `hashicorp/provider-resources` | Provider 资源 | 实现资源和数据源 |
| `hashicorp/provider-test-patterns` | Provider 测试 | 验收测试模式 |
| `hashicorp/terraform-style-guide` | Terraform 风格指南 | HCL 代码风格规范 |
| `hashicorp/terraform-test` | Terraform 测试 | 内置测试框架 |

### 4.7 微软官方技能

| 技能 | 名称 | 描述 |
|------|------|------|
| `microsoft/azure-ai` | Azure AI 服务 | AI Search、Speech、OpenAI、文档智能 |
| `microsoft/azure-messaging` | Azure 消息服务 | Event Hubs 和 Service Bus 诊断 |

### 4.8 其他知名官方技能

<table>
<thead>
<tr style="background-color: #2c3e50; color: white;">
<th>厂商</th><th>技能</th><th>描述</th>
</tr>
</thead>
<tbody>
<tr style="background-color: #f6f8fa;"><td><strong>OpenAI</strong></td><td>openai-docs / skills</td><td>OpenAI SDK 和文档查找</td></tr>
<tr><td><strong>Supabase</strong></td><td>supabase/postgres-best-practices</td><td>PostgreSQL 最佳实践</td></tr>
<tr style="background-color: #f6f8fa;"><td><strong>MongoDB</strong></td><td>mongodb/skills</td><td>MongoDB 开发技能</td></tr>
<tr><td><strong>Redis</strong></td><td>redis/redis-development</td><td>Redis 开发最佳实践</td></tr>
<tr style="background-color: #f6f8fa;"><td><strong>Firebase</strong></td><td>firebase/skills</td><td>Firebase 开发技能</td></tr>
<tr><td><strong>Flutter</strong></td><td>flutter/skills</td><td>Flutter 开发技能</td></tr>
<tr style="background-color: #f6f8fa;"><td><strong>Expo</strong></td><td>expo/skills</td><td>React Native Expo 开发</td></tr>
<tr><td><strong>Sentry</strong></td><td>sentry/skills</td><td>Sentry 错误追踪</td></tr>
<tr style="background-color: #f6f8fa;"><td><strong>Hugging Face</strong></td><td>huggingface/skills</td><td>AI 模型和推理技能</td></tr>
<tr><td><strong>Figma</strong></td><td>figma/skills</td><td>设计工具集成</td></tr>
<tr style="background-color: #f6f8fa;"><td><strong>Auth0</strong></td><td>auth0/skills</td><td>身份认证技能</td></tr>
<tr><td><strong>Notion</strong></td><td>notion/skills</td><td>Notion API 集成</td></tr>
<tr style="background-color: #f6f8fa;"><td><strong>Coinbase</strong></td><td>coinbase/skills</td><td>加密货币开发</td></tr>
<tr><td><strong>Binance</strong></td><td>binance/skills</td><td>交易所 API 集成</td></tr>
</tbody>
</table>

---

## 5. 社区贡献技能库精选

社区贡献是 Agent Skills 生态最活跃的部分。以下精选来自 awesome-agent-skills 仓库中评价最高的社区技能：

### 5.1 工程与开发

| 技能包 | 作者 | 描述 |
|--------|------|------|
| **obra/superpowers** | obra | Claude Code 超能力集，包含 brainstorming、systematic-debugging、requesting-code-review 等 20+ 个开发技能 |
| **mattpocock/skills** | Matt Pocock | 包含 grill-me、to-prd、to-issues、tdd、improve-codebase-architecture 等高质量技能 |
| **callstackincubator/github** | CallStack | GitHub 工作流模式：PR、代码审查、分支管理 |
| **callstackincubator/react-native-best-practices** | CallStack | React Native 性能优化 |
| **callstackincubator/upgrading-react-native** | CallStack | React Native 升级工作流 |

### 5.2 向量数据库与数据工程

| 技能 | 描述 |
|------|------|
| **clickhouse/clickhouse-best-practices** | ClickHouse 最佳实践 |
| **clickhouse/chdb-datastore** | pandas 替代方案，跨 16+ 数据源 |
| **clickhouse/clickhouse-architecture-advisor** | ClickHouse 架构设计 |
| **neondatabase/neon-postgres** | Neon Serverless Postgres 最佳实践 |
| **tinybirdco/tinybird-best-practices** | Tinybird 数据管线和 SQL 指南 |
| **redis/redis-development** | Redis 数据结构、向量搜索、缓存优化 |

### 5.3 前端与 UI

| 技能 | 描述 |
|------|------|
| **angular/angular-developer** | Angular 组件、服务、响应式架构 |
| **vercel-labs/react-best-practices** | React 前端性能优化 |
| **vercel-labs/web-design-guidelines** | 无障碍和设计合规性审计 |
| **remotion-dev/remotion** | 编程化视频创建 |
| **dify/dify-frontend-tester** | React 前端测试（Vitest + Testing Library） |

### 5.4 安全

| 技能 | 发布者 | 描述 |
|------|--------|------|
| **Trail of Bits 安全技能** | Trail of Bits | 专业安全审计和代码分析 |
| **ffuf-web-fuzzing** | 社区 | Web 模糊测试和渗透测试 |
| **CodeRabbit 技能** | CodeRabbit | AI 驱动的代码审查 |
| **Snyk Skill Security Scanner** | Snyk | 技能安全扫描工具 |

### 5.5 市场营销与产品管理

| 技能 | 作者 | 描述 |
|------|------|------|
| **corey-haines/marketing** | Corey Haines | 市场营销策略和内容创作 |
| **kim-barrett/advertising** | Kim Barrett | 广告技能集 |
| **dean-peters/product-manager** | Dean Peters | 产品经理技能 |
| **pawel-huryn/product-management** | Paweł Huryn | 产品管理技能 |

### 5.6 自动化与协作

| 技能 | 描述 |
|------|------|
| **n8n-automation** | n8n 工作流自动化 |
| **typefully/typefully** | 跨平台社交媒体内容发布（X/LinkedIn/Threads/Bluesky/Mastodon） |
| **courier/courier-skills** | 多渠道通知（邮件/SMS/推送/聊天） |
| **better-auth/skills** | 身份认证：邮箱密码、2FA、组织管理 |

---

## 6. 如何创建自己的 Agent Skill

### 6.1 快速开始

创建 Agent Skill 比你想象的要简单得多。以下是最小可行的 SKILL.md 示例：

```markdown
---
name: my-custom-skill
description: 这是我的第一个技能，用于执行特定任务
---

当用户要求进行 X 任务时，请按以下步骤操作：

1. 首先，收集必要信息：...
2. 然后，分析数据：...
3. 最后，输出结果：...

## 注意事项
- 注意边界条件 A
- 避免使用 B 方法

## 示例

用户："做 X"
助手：（按照上述流程执行）
```

### 6.2 技能质量标准

根据 awesome-agent-skills 仓库定义的质量标准，一个好的技能应该满足：

| 领域 | 标准 |
|------|------|
| **描述** | 使用第三人称，说明技能做什么、何时使用。使用 Agent 可匹配的具体关键词 |
| **渐进式披露** | 顶层元数据控制在 ~100 tokens 内。技能正文不超过 500 行。大文档通过引用加载 |
| **无绝对路径** | 禁止硬编码机器特定路径。使用相对路径或环境变量 |
| **范围化工具** | 只请求技能实际需要的工具。禁止使用通配符 `"tools": ["*"]` |

### 6.3 使用 skill-creator 创建

推荐使用 Anthropic 官方的 `skill-creator` 技能创建新技能：

1. 安装：`npx skills add anthropics/skills`
2. 激活：告诉你的 Agent "我想创建一个新技能"
3. Agent 会引导你通过交互式 Q&A 完成创建
4. 自动生成包含 YAML frontmatter 和结构化指令的 SKILL.md
5. 技能会并行运行测试用例，对比有/无技能的表现
6. 提供交互式审查工具显示输出和基准指标

### 6.4 最佳实践建议

1. **从小开始**：像 Matt Pocock 的 grill-me 技能只有三句话，但效果惊人
2. **聚焦单一职责**：一个技能只做一件事，做好
3. **提供具体示例**：好的示例胜过千言万语
4. **包含边界条件**：明确告诉 Agent 什么情况下不应该使用这个技能
5. **迭代优化**：使用 skill-creator 的评估功能持续改进
6. **关注社区反馈**：发布到社区后收集反馈不断迭代

---

## 7. 平台兼容性与安装指南

### 7.1 各平台技能路径

Agent Skills 已成为跨平台标准，以下是各工具的技能目录路径：

| 工具 | 项目级路径 | 全局路径 |
|------|-----------|---------|
| **Claude Code** | `.claude/skills/` | `~/.claude/skills/` |
| **Codex** | `.agents/skills/` | `~/.agents/skills/` |
| **Gemini CLI** | `.gemini/skills/` | `~/.gemini/skills/` |
| **Cursor** | `.cursor/skills/` | `~/.cursor/skills/` |
| **GitHub Copilot** | `.github/skills/` | `~/.copilot/skills/` |
| **Windsurf** | `.windsurf/skills/` | `~/.codeium/windsurf/skills/` |
| **OpenCode** | `.opencode/skills/` | `~/.config/opencode/skills/` |
| **Antigravity** | `.agent/skills/` | `~/.gemini/antigravity/skills/` |

### 7.2 统一安装命令

使用 Skills CLI 可以跨平台安装：

```bash
# 安装单个技能
npx skills@latest add <author>/<repository>

# 例如：安装 Matt Pocock 的技能包
npx skills@latest add mattpocock/skills

# 搜索可用技能
npx skills find <关键词>

# 列出已安装的技能
npx skills list
```

### 7.3 手动安装

也可以从 GitHub 仓库手动安装：

```bash
# 克隆技能仓库
git clone https://github.com/author/skills-repo.git

# 将技能复制到对应工具的技能目录
cp -r skills-repo/skills/my-skill .claude/skills/
```

---

## 8. Agent Skills 的安全注意事项

### 8.1 潜在风险

在享受 Agent Skills 带来的强大能力时，也需要保持警惕：

1. **提示注入（Prompt Injection）**：恶意技能可能包含隐藏的提示注入攻击
2. **工具投毒（Tool Poisoning）**：技能可能请求不必要的工具权限
3. **隐藏载荷（Hidden Payloads）**：脚本中可能包含恶意代码
4. **不安全的数据处理**：技能可能不安全地处理用户数据

### 8.2 安全建议

- **审查来源**：优先安装官方或高信誉作者的技能
- **检查代码**：安装前查看 SKILL.md 和关联脚本
- **最小权限**：只安装真正需要的技能，定期清理不再使用的
- **使用安全工具**：
  - [Snyk Skill Security Scanner](https://github.com/snyk/agent-scan) — 技能安全扫描
  - [Agent Trust Hub](https://ai.gendigital.com/agent-trust-hub) — Agent 信任中心
- **关注更新**：技能可能被原始维护者更新、修改或替换

### 8.3 awesome-agent-skills 的安全声明

> "此列表中的技能经过精选，但未经审计。它们可能随时被原始维护者更新、修改或替换。在安装或使用任何 Agent Skill 之前，请自行审查潜在安全风险并验证来源。"

---

## 9. 未来趋势与展望

### 9.1 技能市场的爆发

截至 2026 年 5 月，已有超过 31,000 个技能在流通。预计到 2026 年底，这个数字将突破 100,000。随着更多企业和开发者加入，技能的质量和专业化程度将持续提升。

### 9.2 企业级技能

企业正在将内部流程和专有知识封装为私有技能。这种现象类似于早期 Kubernetes 的 Operator 模式——企业会拥有自己的"技能目录"，包含合规检查、部署流程、安全策略等。

### 9.3 技能货币化

随着技能生态成熟，高级技能或将出现付费模式。类似于 GitHub Sponsors 或 VSCode 扩展市场，优秀技能作者可以通过技能获得收益。

### 9.4 自主技能生成

AI Agent 将能根据任务需求自主编写和优化技能。Anthropic 的 skill-creator 已经是第一步，未来 Agent 可能自动分解复杂任务、生成对应技能、测试并部署。

### 9.5 跨平台技能标准统一

目前各平台的技能路径和功能略有差异，未来很可能出现统一的标准，让"一次编写，到处运行"成为现实。officialskills.sh 已经是这个方向的尝试。

### 9.6 技能与 MCP 的融合

Model Context Protocol (MCP) 作为 Agent 与外部世界交互的标准协议，正在与 Skills 生态深度融合。技能提供"怎么做"的指导，MCP 提供"与什么交互"的连接能力。

---

## 10. 总结：我的终极推荐清单

### 🎯 新手必装（5 个）

如果你今天第一次接触 Agent Skills，这是你的起点：

| 顺序 | 技能 | 理由 |
|------|------|------|
| 1️⃣ | **Skill Installer** | 先装上商店，其他技能随时搜随时装 |
| 2️⃣ | **Prompt Lookup** | 立即提升所有对话的质量 |
| 3️⃣ | **grill-me** | 彻底改变你与 AI 沟通的方式 |
| 4️⃣ | **Anthropic PDF** | 日常文档处理必备 |
| 5️⃣ | **skill-creator** | 学会自己创建技能，进入进阶阶段 |

### 🚀 开发者进阶（+5 个）

如果你是开发者，在上述基础上加装：

| 顺序 | 技能 | 理由 |
|------|------|------|
| 6️⃣ | **React Best Practices** | 前端质量保障 |
| 7️⃣ | **TDD (Matt Pocock)** | 测试驱动开发闭环 |
| 8️⃣ | **Systematic Debugging** | 系统化根因分析 |
| 9️⃣ | **Improve Codebase Architecture** | 让代码库更"AI 友好" |
| 🔟 | **Agentic Eval** | 质量管理自动化 |

### 💼 专业场景（+5 个）

| 场景 | 推荐技能 |
|------|---------|
| 视频内容创作 | Remotion Video Editor |
| 网页数据采集 | Firecrawl Build 系列 |
| 基础设施即代码 | HashiCorp Terraform 技能集 |
| 社交媒体管理 | Typefully |
| 安全测试 | Trail of Bits / ffuf-web-fuzzing |

### 📊 最终榜单：Top 10 不可错过的 Agent Skills

```
┌─────┬──────────────────────────────┬──────────────────┬──────────┐
│ 排名 │ 技能名称                      │ 发布者            │ 类别      │
├─────┼──────────────────────────────┼──────────────────┼──────────┤
│  1  │ Prompt Lookup                │ 社区              │ 通用      │
│  2  │ Skill Installer & Lookup     │ 社区              │ 通用      │
│  3  │ grill-me                     │ Matt Pocock       │ 开发流程  │
│  4  │ React Best Practices         │ Vercel            │ 前端开发  │
│  5  │ TDD (Test-Driven Dev)        │ Matt Pocock       │ 开发流程  │
│  6  │ Web Design Audit Guidelines  │ Vercel            │ 设计/无障碍│
│  7  │ PDF Toolkit (Anthropic)      │ Anthropic         │ 文档处理  │
│  8  │ skill-creator (Anthropic)    │ Anthropic         │ 元技能    │
│  9  │ Systematic Debugging          │ obra/superpowers  │ 调试      │
│ 10  │ Agentic Eval                 │ GitHub            │ 质量评估  │
└─────┴──────────────────────────────┴──────────────────┴──────────┘
```

### 结语

Agent Skills 正在重塑我们与 AI 协作的方式。它们不仅仅是"插件"或"扩展"——它们是将人类专业知识编码为 AI 可执行流程的桥梁。在这个 Agent 能力快速扩张的时代，掌握并使用好的 Agent Skills，意味着你不再只是使用 AI，而是真正在**工程化地驾驭 AI**。

正如 Matt Pocock 所说："技能不必很长才能产生影响。你只需要在正确的时间选择正确的表达。"

现在就开始安装你的第一个技能吧：

```bash
npx skills@latest add mattpocock/skills
```

从此，你的 AI Agent 将拥有真正的"专业技能"。

---

*本报告基于 2026 年 5 月的公开信息编写，Agent Skills 生态发展迅速，建议定期关注 [awesome-agent-skills](https://github.com/VoltAgent/awesome-agent-skills) 和 [officialskills.sh](https://officialskills.sh/) 获取最新信息。*

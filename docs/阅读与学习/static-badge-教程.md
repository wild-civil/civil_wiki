---
title: Static Badge 完全教程
tags: [MkDocs, 前端, 教程, shields.io]
---

# Static Badge 完全教程

> 本文解答三个问题：① 什么是 static badge、链接是怎么拼出来的；② 为什么有的 badge「能点击跳转」、有的「带外边框」；③ 如何复刻 [wiki-power.com](https://wiki-power.com/) 那种干净的首页 badge。
> 适用场景：MkDocs / Material 主题、Obsidian 发布、GitHub README、任何支持 Markdown 的地方。

---

## 1. 什么是 Static Badge

「Badge（徽章）」就是那种左边一个灰底标签、右边一个彩色值的小长条，常见于开源项目主页：

```
[ build | passing ]   [ license | MIT ]   [ version | v1.2.3 ]
```

「Static（静态）」指的是**徽章上的文字是你写死在 URL 里的**，不是实时查出来的。与之相对的是 Dynamic Badge（动态徽章），比如「GitHub 最后提交时间」「最新 Release 版本」，那是 shields.io 去实时请求 GitHub API 算出来的。

最常用、零依赖的服务是 [shields.io](https://shields.io/)。它的静态徽章端点统一是：

```
https://img.shields.io/badge/<LABEL>-<MESSAGE>-<COLOR>
```

- **LABEL**：左半边灰底文字（如 `build`、`Last commit`）
- **MESSAGE**：右半边彩色文字（如 `passing`、`2026-07-17`）
- **COLOR**：右半边的底色（命名色 / 十六进制 / rgb）

举几个最小例子（复制到浏览器即可看到图）：

| 你想显示 | URL |
| --- | --- |
| `build \| passing`（绿） | `https://img.shields.io/badge/build-passing-brightgreen` |
| `license \| MIT`（蓝） | `https://img.shields.io/badge/license-MIT-blue` |
| `版本 \| v1.2.3`（橙） | `https://img.shields.io/badge/版本-v1.2.3-orange` |

> 注意：中文可以直接写在 URL 里（shields.io 支持 UTF-8），但**空格必须编码成 `%20`**，否则链接会断。

---

## 2. URL 的完整拼装规则

### 2.1 字段分隔：单横杠 vs 双横杠

静态徽章的 URL 用「单个 `-`」分隔三个字段。但如果 LABEL 或 MESSAGE 本身需要连字符（比如日期 `2026-07-17`），就要把真正的连字符写成 **`--`（双横杠）**，shields 会把 `--` 渲染回单个 `-`。

```
badge/Last%20commit-2026--07--17-orange
        └─LABEL─┘ └─MESSAGE(2026-07-17)─┘ └色┘
```

- `Last%20commit` → 左字 `Last commit`
- `2026--07--17` → 右字 `2026-07-17`（`--` 变 `-`）
- `orange` → 橙色底

### 2.2 颜色 COLOR

| 写法 | 示例 | 说明 |
| --- | --- | --- |
| 命名色 | `brightgreen` `green` `yellow` `orange` `red` `blue` `lightgrey` `informational` | 最稳，推荐 |
| 十六进制 | `ff69b4` `9cf` | **不要带 `#`**，直接写 6 位（或 3 位） |
| rgb | `rgb(255,105,180)` | 需要 URL 编码括号和逗号 |

常用命名色速查：`brightgreen` `green` `yellowgreen` `yellow` `orange` `red` `blue` `lightblue` `purple` `pink` `grey` `lightgrey` `black` `white` `informational` `success` `critical` `important` `orange` `yellow`。

### 2.3 风格 style（最重要的一步：去「圆角凸起」感）

默认 `style=flat` 是左边灰、右边彩、整体有轻微立体阴影。wiki-power 用的是 **`flat-square`**（左右齐平、无阴影、最简洁）。其它可选：

| style | 观感 |
| --- | --- |
| `flat`（默认） | 左右分色，轻微阴影 |
| `flat-square` | 左右齐平，无阴影（推荐，最像 wiki-power） |
| `plastic` | 强立体高光 |
| `for-the-badge` | 大写粗体、大圆角（适合社交类） |
| `social` | 仿 GitHub 社交按钮 |

加风格只需在 URL 末尾加 `?style=flat-square`：

```
https://img.shields.io/badge/知识库-Wiki-blue?style=flat-square
```

### 2.4 左底色 labelColor

想让左半边也变色？加 `&labelColor=`：

```
https://img.shields.io/badge/SSPAI-subscribe-blue?style=flat-square&labelColor=d71a1b
```

### 2.5 加图标 logo

加 `&logo=<slug>`，slug 来自 [Simple Icons](https://simpleicons.org/)（小写、连字符）：

```
https://img.shields.io/badge/GitHub-follow-blue?style=flat-square&logo=github
```

（`logoColor` 可改图标颜色；`link` 参数见下一节）

---

## 3. 让它「能点击跳转」——关键之一

shields.io 只管**出图**。图本身是个 `<img>`，默认不跳转。要让它可点，有两种办法：

### 办法 A：用 Markdown 链接把图片包起来（最通用，推荐）

语法是 `[![alt 文字](图片URL)](点击后跳转的URL)`：

```markdown
[![badge](https://img.shields.io/badge/硬件与半导体-Hardware-9cf?style=flat-square)](/硬件与半导体/)
```

渲染出来：点击徽章 → 跳到 `/硬件与半导体/` 页面。

> 这正是 wiki-power 首页的做法：他把每个 badge 都用链接包起来，所以「能跳转」。
> 我一开始写的是裸 `![...]`（没有外层链接），所以不跳转——这就是差异来源。

### 办法 B：用 shields 的 `link` 查询参数（嵌 HTML 时用）

如果你是直接写 `<img>` 标签，可以给 shields 传 `&link=目标URL`：

```
https://img.shields.io/badge/xxx-yyy-blue?style=flat-square&link=https://example.com
```

但在 Markdown 里，**办法 A 更简单、可读性更好**，优先用 A。

---

## 4. 让它「没有外边框」——关键之二

Material 主题（以及很多自定义 CSS）会给正文里的**所有图片**加边框/描边，让徽章也跟着「框起来」。wiki-power 的徽章没边框，是因为他用了**一箭双雕**的技巧：

### 4.1 给徽章图设 `alt="badge"`

Markdown 里 `[![badge](图)](链)` 的**第一个括号**就是 `alt` 文本。把它写成字面的 `badge`：

```markdown
[![badge](https://img.shields.io/badge/知识库-Wiki-blue?style=flat-square)](/)
```

### 4.2 在 `extra.css` 里把 `alt="badge"` 排除出边框规则

```css
/* 普通图片加黑描边，但徽章(badge)和 logo 不加 */
img:not([alt="badge"]):not([alt="logo"]) {
  max-width: 100%;
  border: 2px solid #000;
  border-radius: 2px;
  background: white;
  padding: 3px;
}
```

`img:not([alt="badge"])` 的意思是「选中所有 **alt 不是 badge** 的图片」。因为徽章的 alt 正好是 `badge`，所以被排除，**自然就没有边框了**。

> 我第一次翻车时，徽章的 alt 写的是 `Last commit`、`Contact & Subscribe` 这种描述文字，不是字面的 `badge`，于是 `:not([alt="badge"])` 判定为真，边框照样套上去了。改成 `alt="badge"` 后立刻干净。

### 4.3 顺手加 `loading=lazy`（可选但推荐）

在图片 URL 后加 `{ loading=lazy }`（Material / Python-Markdown 的属性列表语法），让徽章延迟加载、首页更快：

```markdown
[![badge](https://img.shields.io/badge/知识库-Wiki-blue?style=flat-square){ loading=lazy }](/)
```

---

## 5. 实战：复刻 wiki-power 首页 badge

下面就是本知识库首页（`docs/README.md`）实际在用的写法，**可直接照抄**：

```markdown
# 我的知识库

[![badge](https://img.shields.io/badge/Last%20commit-2026--07--17-orange?style=flat-square){ loading=lazy }](#)
[![badge](https://img.shields.io/badge/Contact%20%26%20Subscribe-me-blue?style=flat-square){ loading=lazy }](#)

[![badge](https://img.shields.io/badge/知识库-Wiki-blue?style=flat-square){ loading=lazy }](/)
[![badge](https://img.shields.io/badge/硬件与半导体-Hardware-9cf?style=flat-square){ loading=lazy }](/硬件与半导体/)
[![badge](https://img.shields.io/badge/技术与编程-Tech-brightgreen?style=flat-square){ loading=lazy }](/技术与编程/)
[![badge](https://img.shields.io/badge/阅读与学习-Read-yellow?style=flat-square){ loading=lazy }](/阅读与学习/)
[![badge](https://img.shields.io/badge/生活与兴趣-Life-orange?style=flat-square){ loading=lazy }](/生活与兴趣/)
[![badge](https://img.shields.io/badge/博客-Blog-ff69b4?style=flat-square){ loading=lazy }](/博客/)
```

要点回顾：

1. 每个 badge 都是 `[![badge](...)](...)` —— **alt 字面写 `badge` + 外层链接包裹**。
2. 风格统一 `?style=flat-square`。
3. 跳转目标用站内相对路径（`/硬件与半导体/`）或 `#` 占位；没有公网仓库时 `Last commit` / `Contact` 先用 `#`，等有了再换成真实地址。
4. `extra.css` 里有 `img:not([alt="badge"])` 规则 → 徽章无边框。

首页下方还用 `.md-button` 做了几个大按钮（Material 的按钮样式）：

```markdown
[硬件 & 半导体](/硬件与半导体/){ .md-button }
[技术与编程](/技术与编程/){ .md-button }
[阅读与学习](/阅读与学习/){ .md-button }
```

---

## 6. Static vs Dynamic 徽章

| 维度 | Static（静态） | Dynamic（动态） |
| --- | --- | --- |
| 文字来源 | 写死在 URL | shields 实时请求接口算出 |
| 是否需要联网仓库 | 否 | 是（GitHub / npm / 自定义 API） |
| 示例 | `badge/build-passing-green` | `badge/github/last-commit/owner/repo` |
| 适合 | 分类标签、联系方式、标语 | 构建状态、版本号、订阅数 |
| 失效风险 | 几乎不会（除非 shields 挂了） | 仓库私有 / API 限流会挂 |

动态徽章示例（需要公开 GitHub 仓库）：

```
https://img.shields.io/github/last-commit/linyuxuanlin/Wiki_MkDocs?style=flat-square
https://img.shields.io/github/v/release/owner/repo?style=flat-square
```

个人知识库在没推到公网前，**用 static 就够了**；等哪天把仓库推到 GitHub，再把 `Last commit` 换成上面那条动态链接即可。

> 进阶：shields.io 还支持 `badge/dynamic/json?url=...&query=...` 从任意 JSON API 取数（wiki-power 的订阅数徽章就是这么做的），但那属于动态范畴，本文不展开。

---

## 7. 常见坑 & 排查

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| 徽章不显示 / 裂图 | URL 里有未编码的空格 | 空格改成 `%20` |
| 徽章带丑边框 | `alt` 不是字面 `badge`，或 CSS 没排除 | 把 alt 改成 `badge`，并在 `extra.css` 加 `:not([alt="badge"])` |
| 点徽章没反应 | 写成了裸 `![...]` 没包链接 | 改成 `[![badge](...)](目标URL)` |
| 日期里的 `-` 显示成两道 | 用了单 `-` 当分隔 | 真正的连字符写成 `--`（双横杠） |
| 颜色不生效 | 写了 `#ff69b4` | 去掉 `#`，写 `ff69b4` |
| 构建报「找不到目标页」 | 链接指向了不存在的站内路径 | 确认导航里该页真实存在 |
| 中文标签有时乱码 | 某些老旧渲染器 | 尽量用 ASCII 标签，或确保 UTF-8 |

---

## 8. 一句话总结

> **干净的 badge = `alt="badge"`（去边框） + 外层 Markdown 链接（能跳转） + `?style=flat-square`（简洁风）。**
> 这三件套，就是 wiki-power 首页徽章的全部秘密。

需要更多样式灵感，直接去 [shields.io 静态徽章 playground](https://shields.io/badges) 拖一拖就懂了。

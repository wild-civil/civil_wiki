---
title: 建站笔记：GitHub Pages 的 main 与 gh-pages 分支到底什么关系
date: 2026-07-19
tags:
  - 建站
  - GitHub Pages
  - 教程
---

# 建站笔记：GitHub Pages 的 main 与 gh-pages 分支到底什么关系

> 把静态站部署到 GitHub Pages 时，仓库里几乎总会出现两个分支：`main` 和 `gh-pages`。
> 很多人（包括我）一开始都搞混过——把 Pages 的 **Source** 误设成 `main`，结果站点 404、
> 自定义域名的 HTTPS 也起不来。这篇把这两个分支的分工、Pages 的工作原理、以及最常见的坑讲清楚。

---

## 一、先说结论

- **`main` = 源分支**：放「原料」——Markdown、`mkdocs.yml`、`config.toml`、Hugo 源文件、图片源等。
  它的根目录**没有**可直接打开的 `index.html`，不能当成品网站用。
- **`gh-pages` = 构建产物分支**：放「成品」——`mkdocs build` / `hugo` 生成的 HTML / CSS / JS。
  这才是真正能被浏览器访问的网站。
- **GitHub Pages 的 Source 必须指向 `gh-pages`**（即含成品的分支），不是 `main`。
  选错 → 404，因为 `main` 里根本没有能服务的首页。

一句话：**`main` 是人写的，`gh-pages` 是机器生成的；Pages 只认 `gh-pages`。**

---

## 二、GitHub Pages 怎么工作的

GitHub Pages 本质上是一个「静态文件服务器」：你告诉它

> 「去 **某个分支** 的 **某个目录** 下，把文件当网站根目录serve 出去。」

- 当你在 `Settings → Pages → Source` 选 `gh-pages` / `root`（或 `docs/`）时，
  GitHub 就会把那个分支里的文件直接映射成 `https://<user>.github.io/<repo>/`，
  再加上你配的自定义域名（如 `nav.hanvon.top`）。
- 它**不会**帮你构建。如果分支里只有 `.md` 源文件、没有 `.html`，访客就只会拿到一堆
  源码或 404，而不是网站。

所以「源码分支」永远不能直接当 Source。中间必须有一道「构建」把源变成 HTML，
而 `gh-pages` 就是这道构建的**产出落点**。

---

## 三、MkDocs 与 Hugo 殊途同归

不管你用哪个引擎，**项目页（Project Pages）的成品最终都落在 `gh-pages`**：

| 引擎 | 构建命令 | 谁把产物推到 `gh-pages` | Pages Source |
|---|---|---|---|
| MkDocs | `mkdocs build` | `mkdocs gh-deploy --force` | `gh-pages` |
| Hugo | `hugo` | `peaceiris/actions-gh-pages`（CI）或手动 `git push` | `gh-pages` |

流程对比：

```
main（源码）                  gh-pages（成品）
┌──────────┐   build    ┌──────────────┐
│ .md/.yml │ ────────▶  │ index.html   │ ──▶ Pages serve
│ /config  │            │ *.css / *.js │
└──────────┘            └──────────────┘
  人维护                    机器生成
```

> 关键点：**迁移引擎（MkDocs↔Hugo）后，`Settings → Pages` 完全不用改**——
> 因为产物分支始终是 `gh-pages`。你只换「构建工具」和「怎么把产物推上去」。

---

## 四、自定义域名（CNAME）放哪

自定义域名要出现在**成品根目录**的 `CNAME` 文件里，Pages 才能签发证书并生效。
但「源」里的位置因引擎而异：

| 引擎 | `CNAME` 在源里放哪 | 怎么到成品根 |
|---|---|---|
| MkDocs | `docs/CNAME` | `mkdocs build` 把 `docs/` 整体编译，CNAME 留在根 |
| Hugo | `static/CNAME` | Hugo 把 `static/` 原样复制到站点根 |

放错位置的典型症状：`gh-pages` 根没有 `CNAME` → 自定义域名 HTTPS 失效，回退到 `github.io`。

---

## 五、最常见的坑：Source 选成了 main

**症状**：`https://<自定义域名>` 访问 404，或 HTTPS 握手失败（TLS 起不来）。

**根因**：在 `Settings → Pages → Source` 选了 `main` 而非 `gh-pages`。
`main` 里只有源码，没有可服务的 `index.html`，自然 404。

**排查与修复**：

1. 进仓库 `Settings → Pages`，看 **Source** 当前指向哪个分支。
2. 若不是 `gh-pages`，改成 `gh-pages` / `(root)`。
3. 确认 **Custom domain** 填的是你的域名（如 `nav.hanvon.top`），且 DNS check 通过
   （DNS 里应有 `CNAME  <你的域名> → <user>.github.io`）。
4. 仓库需为 **Public**（私有仓库的 Pages 需要 GitHub Pro/Team，公开项目免费）。
5. 改完后等 1–2 分钟让 Actions 重跑、证书签发，再访问。

> 真实案例：我的 `works.hanvon.top` 一开始 404，就是因为 Source 误设为 `main`；
> 改回 `gh-pages` 后立即恢复 HTTP 200 + HTTPS。

---

## 六、一眼看懂：两分支对照表

| 维度 | `main` | `gh-pages` |
|---|---|---|
| 角色 | 源码 / 人维护 | 成品 / 机器生成 |
| 典型内容 | `.md`、`mkdocs.yml`、`config.toml`、`layouts/`、`static/` | `index.html`、`*.css`、`*.js`、`CNAME` |
| 能否直接访问 | ❌ 不能（无服务用首页） | ✅ 能（被 Pages serve） |
| 谁来写 | 你 `git push` | `mkdocs gh-deploy` / CI / 手动推送 |
| Pages Source 应选它？ | ❌ 否 | ✅ 是 |
| 能否看到网站 | 要看构建产物 | 就是网站本身 |

---

## 七、重要例外：用户页（User Pages）为什么「就是 main」

上面「成品落在 `gh-pages`」是**项目页（Project Pages）**的默认行为。但 GitHub Pages 还有
一种特殊仓库——**用户页 / 组织页（User / Org Pages）**：

- 仓库名必须恰好是 `<用户名>.github.io`（例如 `wild-civil.github.io`）。
- GitHub **默认直接从 `main`/`master` 分支的根目录** serve，**不经过 `gh-pages`**。
- 站点地址就是 `https://<用户名>.github.io/`（没有 `/仓库名` 后缀）。

所以本站最早用 Hexo 搭的博客，仓库就是 `wild-civil.github.io`，它的成品（Hexo 构建出的
`public/` 内容）被直接推到 `main` 分支根目录、Pages 直接 serve——这就是它「就是 main」的原因。

> **关键结论：决定走 `main` 还是 `gh-pages` 的，不是引擎（Hexo/Hugo/MkDocs），而是仓库类型。**
> - 仓库名 = `<用户名>.github.io` → **用户页** → 默认 `main`/`master` 根目录。
> - 其他仓库名（如 `civil_wiki`、`civil_nav`）→ **项目页** → 默认 `gh-pages`。
>
> 当然，用户页也能在 `Settings → Pages` 里手动改成 `gh-pages` 或 `main` 的 `/docs` 目录；
> 只是默认与最常见的做法就是「用户页用默认分支根、项目页用 gh-pages」。
> 本站 `wild-civil.github.io`（Hexo）还配了自定义域名 `blog2.hanvon.top`，因此
> `wild-civil.github.io` 会 301 跳转到 `blog2.hanvon.top`。

| 维度 | 用户页（`<user>.github.io`） | 项目页（其他仓库名） |
|---|---|---|
| 仓库名 | 必须 `<user>.github.io` | 任意 |
| 默认 Source | `main`/`master` 分支根目录 | `gh-pages` 分支 |
| 站点地址 | `https://<user>.github.io/` | `https://<user>.github.io/<repo>/` |
| 典型例子 | `wild-civil.github.io`（Hexo 博客） | `civil_wiki`（MkDocs）、`civil_nav`（Hugo） |

---

## 八、小结

- `main` 是「厨房」，`gh-pages` 是「上菜的盘子」；Pages 只端盘子，不进厨房。
- 部署失败先检查三件事：**Source 是否 gh-pages**、**gh-pages 里有没有 index.html**、
  **CNAME 是否在成品根目录**。
- 引擎怎么换都行，只要产物最终落到 `gh-pages`，Pages 设置一动不用动。

相关：

- [从零搭建多站点 MkDocs（GitHub Pages + 自定义域名） →](建站教程-从零搭建多站点MkDocs.md)
- [Hugo 对照笔记：从 MkDocs 到 Hugo 的迁移与对比 →](建站笔记-Hugo对照.md)
- [Hugo 博客/站点搭建实战 →](建站笔记-Hugo搭建.md)

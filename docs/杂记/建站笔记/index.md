---
title: 建站笔记
date: 2026-07-17
tags:
  - 随笔
  - 知识库
  - 建站
  - MkDocs
  - Hugo
  - Hexo
---

# 建站笔记 / Site Building Notes

这里记录本站（以及姊妹站）的**多站点架构、引擎选型、CI 部署与本地预览**等工程实操笔记。

本站是一个 **多站 monorepo**：一个仓库里放了 5 个子站，各自独立托管在 `*.hanvon.top` 上：

| 子站 | 引擎 | 部署方式 |
|------|------|----------|
| **wiki**（本站） | MkDocs Material | CI → `gh-pages` |
| **digest** | MkDocs | CI → `gh-pages` |
| **nav** | Hugo | CI → `gh-pages` |
| **works** | Hugo | CI → `gh-pages` |
| **博客** | Hexo（Butterfly） | 手动 `hexo d` → 用户页 `main` |

## 笔记条目

- [建站教程 · 从零搭建多站点 MkDocs](建站教程-从零搭建多站点MkDocs.md)
  - 手把手把 MkDocs + GitHub Pages + 自定义域名跑起来，本站的「起点」。
- [全站架构 · 小白篇](建站笔记-全站架构小白篇.md)
  - 最直白的「改哪里、敲哪行命令」版本，先看这篇。
- [全站架构 · 进阶篇](建站笔记-全站架构进阶篇.md)
  - 每个引擎内部怎么运作：目录解剖、模板、CI/CD、自定义主题。
- [多站架构与本地预览](多站架构与本地预览.md)
  - 五站怎么协同、怎么改、怎么编译、怎么在本地看。实操手册版。
- [博客引擎的选择](建站笔记-博客引擎的选择.md)
  - MkDocs / Hugo / Hexo 怎么选，以及我为什么选这三个。
- [GitHub Pages 分支区别](建站笔记-GitHubPages分支区别.md)
  - `main` 与 `gh-pages` 到底什么关系；用户页 vs 项目页。
- [Hugo 搭建](建站笔记-Hugo搭建.md)
  - 从零用 Hugo 搭一个导航站 / 作品集。
- [Hugo 对照](建站笔记-Hugo对照.md)
  - 从 MkDocs 到 Hugo 的迁移与对比。

> 💡 建站踩坑、架构决策都会持续追加到这里。新增笔记直接在 `docs/杂记/建站笔记/` 放文件、并在本页加一条链接即可。

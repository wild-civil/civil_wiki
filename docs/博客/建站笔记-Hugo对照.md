---
title: Hugo 对照笔记：从 MkDocs 到 Hugo 的迁移与对比
date: 2026-07-19
tags:
  - 建站
  - Hugo
  - 教程
---

# Hugo 对照笔记：从 MkDocs 到 Hugo 的迁移与对比

> 本站最早四个子站全是 MkDocs Material。后来发现我喜欢的参考站
> `nav.wiki-power.com` / `works.wiki-power.com` 其实是 **Hugo** 搭的
> （实测 `<meta name="generator" content="Hugo 0.147.7">`），观感是用一套
> 自定义 Bootstrap 主题做的。为了「几乎一致」的视觉，我把 **civil_nav / civil_works**
> 从 MkDocs 重写为 Hugo；知识库 `civil_wiki` 与书摘 `civil_digest` 保留 MkDocs
> （它们依赖 Obsidian `[[wikilink]]` 直转，迁 Hugo 收益低）。
>
> 这篇把 **MkDocs ↔ Hugo** 的关键差异、我怎么用 Hugo 复刻那套观感、以及部署映射记下来。

---

## 一、MkDocs vs Hugo 对照表

| 维度 | MkDocs Material | Hugo |
|---|---|---|
| 引擎 / 语言 | Python | Go（单文件二进制 `hugo`） |
| 内容源 | Markdown + `mkdocs.yml` | Markdown / 数据文件 / 自定义布局 |
| 主题方式 | Material（配置驱动，改 `mkdocs.yml`） | 任意主题，或自写 `layouts/` |
| 构建命令 | `mkdocs build` | `hugo` |
| 部署到 Pages | `mkdocs gh-deploy --force` → `gh-pages` | `hugo` + `actions-gh-pages` → `gh-pages` |
| 站内搜索 | 内置（装 `jieba` 后中文好） | 需客户端方案（如 Pagefind），本站未做 |
| 最适合 | 文档 / 知识库（Obsidian 友好） | 博客 / 作品集 / 导航站 / 任意静态站 |
| 学习曲线 | 低（改 YAML 即可） | 中（要懂 Go 模板 `{{ }}`） |

**结论**：选引擎看**内容源**。纯文档 / Obsidian 笔记 → MkDocs 接入成本最低；
导航站、作品集、或想复刻某个 Hugo 主题的观感 → Hugo 更合适。

---

## 二、Hugo 版 civil_nav 的目录结构

```
civil_nav/
├── config.toml              # baseURL / title / disableKinds / params
├── layouts/
│   └── index.html           # 整页模板：顶栏 + 分区卡片网格 + 页脚
├── static/
│   ├── css/style.css        # 卡片网格样式（自写，非原站私有 CSS）
│   └── CNAME                # nav.hanvon.top（自动复制到站点根）
├── data/
│   └── links.yaml           # 内容数据源：sections → items
├── content/
│   └── _index.md            # 首页占位（保证 home 存在）
└── .github/workflows/ci.yml # actions-hugo 构建 + actions-gh-pages 部署
```

内容由 **数据文件** 驱动，而不是每篇文章一个 Markdown——链接目录天然适合这种结构：

```yaml
# data/links.yaml
sections:
  - title: 我的站点
    items:
      - icon: book
        name: Wiki 知识库
        desc: 我的学习笔记、硬件与嵌入式知识库。
        url: https://wiki.hanvon.top
```

模板里用 `.Site.Data.links.sections` 遍历渲染卡片（`layouts/index.html` 片段）：

```go-html-template
{{ range .Site.Data.links.sections }}
<section class="link-section">
  <h2>{{ .title }}</h2>
  <div class="grid">
    {{ range .items }}
    <a class="card" href="{{ .url }}" target="_blank" rel="noopener noreferrer">
      <div class="card-icon"><i class="fa fa-{{ .icon }}"></i></div>
      <div class="card-body"><h3>{{ .name }}</h3><p>{{ .desc }}</p></div>
    </a>
    {{ end }}
  </div>
</section>
{{ end }}
```

---

## 三、civil_works 的「分类筛选网格」

参考原站 `works.wiki-power.com`：顶部一排分类按钮，下方卡片网格，点按钮按类别过滤。
我用 `data/projects.yaml` 存作品，每个作品带 `categories` 数组；模板把类别拼成
class，再用一小段 `filterSelection()` JS 做显示/隐藏（就是原站那套 W3Schools filter grid）：

```yaml
# data/projects.yaml
categories: [MCU, Linux, Sensor, Power]
items:
  - name: 机器人通用开发套件 - RobotCtrl
    desc: 专为机器人控制设计的 MCU 通用开发套件。
    categories: [MCU]
    website: https://wiki.hanvon.top
    repo: https://github.com/wild-civil
```

```go-html-template
{{ range .Site.Data.projects.items }}
<div class="column {{ delimit .categories " " }}">
  <div class="content">
    {{ with .image }}<img src="{{ . }}" alt="{{ .name }}" />{{ end }}
    <h3>{{ .name }}</h3><p>{{ .desc }}</p>
    <div class="btn-group">
      {{ with .website }}<a ...><button><i class="fa fa-paperclip"></i> Website</button></a>{{ end }}
      {{ with .repo }}<a ...><button><i class="fa fa-github"></i> Repo</button></a>{{ end }}
    </div>
  </div>
</div>
{{ end }}
```

> 想加封面图，给作品加 `image: <url>` 字段即可；不加也能正常显示。

---

## 四、部署对照（最关键差异）

| 步骤 | MkDocs 站（wiki/digest） | Hugo 站（nav/works） |
|---|---|---|
| 构建 | `mkdocs build` | `hugo --minify` |
| 推送到 Pages | `mkdocs gh-deploy --force` | `peaceiris/actions-gh-pages` 推 `./public` |
| 产物分支 | `gh-pages` | `gh-pages` |
| Pages 源设置 | `gh-pages` | `gh-pages`（不变） |
| 自定义域名文件 | `docs/CNAME` | `static/CNAME` |

两者最终都落到 **`gh-pages` 分支 + Pages 源 = gh-pages**，所以迁移后你在
GitHub 的 `Settings → Pages` 完全不用改。Hugo 的 `ci.yml` 核心：

```yaml
- name: Setup Hugo
  uses: peaceiris/actions-hugo@v3
  with:
    hugo-version: "0.147.7"
    extended: true
- run: hugo --minify
- name: Deploy
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./public
```

---

## 五、踩过的坑

1. **Hugo 默认会生成 tag/category 分类页**：哪怕你没用分类，它也会尝试渲染
   `kind: taxonomy` 并抛 WARN。加 `disableKinds = ["taxonomy", "term", "RSS"]` 关掉即可。
2. **`baseURL` 必须设为自定义域名**（`https://nav.hanvon.top/`），否则站内资源路径
   和 `canonical` 会指向 `github.io`。
3. **`CNAME` 放 `static/` 下**，Hugo 会自动复制到站点根；放错位置 → `gh-pages` 根
   没有域名 → HTTPS 失效、回退 `github.io`。
4. **FontAwesome 用 CDN**（运行时 CSS，如 `cdnjs` 的 4.7.0），不影响构建，也不必本地化。
5. **本地先 `hugo --minify` 验证**：能立刻看到 `public/index.html` 与卡片是否渲染，
   比等 CI 报错快得多。CI 用 `peaceiris/actions-hugo@v3` 的 **extended** 版更稳。

---

## 六、小结

- 同一套「Obsidian 写 → push → 自动部署 → 自定义域名 HTTPS」闭环，**MkDocs 和 Hugo 都能跑**，
  区别只在构建工具与主题写法。
- 我当前的分工：**wiki / digest = MkDocs**（文档型、Obsidian 友好）；
  **nav / works = Hugo**（导航 / 作品集，对齐参考站观感）。
- 要不要把 wiki 也转 Hugo？不必——除非你哪天想要某个 Hugo 文档主题的样子。到时按本文第四节的
  部署映射改 `ci.yml` 即可，域名与 DNS 都不用动。

相关：

- [从零搭建多站点 MkDocs（GitHub Pages + 自定义域名） →](建站教程-从零搭建多站点MkDocs.md)
- [域名规划与部署 →](../../阅读与学习/域名规划与部署.md)

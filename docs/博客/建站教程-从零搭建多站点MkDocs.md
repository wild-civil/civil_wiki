---
title: 从零搭建多站点 MkDocs 知识库（GitHub Pages + 自定义域名实战）
date: 2026-07-19
tags:
  - 建站
  - 教程
  - MkDocs
  - GitHub Pages
---

# 从零搭建多站点 MkDocs 知识库

> 本站（wiki / nav / works / digest 四个子站点）就是这样搭出来的。
> 这篇把**完整配方**写下来：选型 → 初始化 → 内容组织 → 自动部署 → 自定义域名 → 一套模板复制成多站，以及我们踩过的每一个坑。

## 我们最终搭出了什么

| 子站点 | 仓库 | 地址 | 内容 |
|---|---|---|---|
| 知识库 | `civil_wiki` | `wiki.hanvon.top` | Obsidian 笔记 / 硬件 / 嵌入式 |
| 导航 | `civil_nav` | `nav.hanvon.top` | 我的站点 + 友链 + 工具入口 |
| 作品集 | `civil_works` | `works.hanvon.top` | 硬件作品与开源项目 |
| 书摘 | `civil_digest` | `digest.hanvon.top` | 读书摘录（建设中） |

四个站**全部用 MkDocs Material 生成**，托管在 **GitHub Pages**，
各自绑定 `hanvon.top` 下的子域名，享受 GitHub 提供的**免费 TLS 证书**（HTTPS 自动绿锁）。

整体架构长这样：

![多站点架构](../assets/images/hanvon-top-arch.svg)

---

## 一、技术选型：为什么是 MkDocs + GitHub Pages

**MkDocs Material**（`mkdocs-material`）是我选的文档主题，理由：

- 纯 Markdown 写作，和 Obsidian 笔记几乎零摩擦（`[[wikilink]]` 也能自动转链接）；
- 自带全文搜索、深色模式、代码复制、标签聚合、Mermaid 图；
- 中文界面完善（`language: zh`），颜值高、移动端自适应；
- 网格卡片（`.grid.cards`）天然适合做导航站 / 作品集。

**GitHub Pages** 作为托管：

- 公开仓库**免费**托管静态站；
- 支持自定义域名，并**免费签发 HTTPS 证书**；
- 配合 GitHub Actions 可做到「push 即部署」，不用手动上传。

> **关于引擎的一点说明**：你可能见过 `nav.wiki-power.com` 那种风格——它其实是用 **Hugo**（`<meta name="generator" content="Hugo 0.147.7">`）搭的，和我们这里的 MkDocs 不是同一种引擎。
> 两者都能做出几乎一样的网格卡片观感。**选哪个取决于你的内容源**：如果你的笔记来自 Obsidian / 纯 Markdown，MkDocs 接入成本最低；如果你更习惯 Hugo 的内容模型，用 Hugo 也完全没问题。本教程只讲我们已经跑通的 MkDocs 方案。

---

## 二、环境准备

只需要 Python 3.x（建议 3.10+）。

```bash
# 任选一个虚拟环境方式
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate

pip install -r requirements.txt
```

本站的 `requirements.txt` 内容（可直接复用）：

```text
mkdocs-material>=9.5
mkdocs-roamlinks-plugin          # Obsidian [[wikilink]] -> 站点链接
mkdocs-git-revision-date-localized-plugin   # 每页显示「最后更新时间」
mkdocs-minify-plugin             # 压缩 HTML/CSS/JS
jieba                            # 中文搜索分词
Pillow                           # 生成社交分享卡片
```

装好后用 `mkdocs --version` 验证，`mkdocs serve` 可在本地 `http://127.0.0.1:8000` 实时预览。

---

## 三、步骤一：`mkdocs.yml` 核心配置

每个站点根目录一个 `mkdocs.yml`。一份**最小可用 + 本站关键项**的配置骨架：

```yaml
site_name: 我的知识库
site_description: 基于 Obsidian Vault 构建的个人知识库文档站

# 关键：填你的自定义域名（决定资源路径 / canonical / Sitemap）
site_url: https://wiki.hanvon.top/

# GitHub 仓库（启用后顶栏出现仓库图标 + 每页「Edit on GitHub」）
repo_url: https://github.com/wild-civil/civil_wiki
edit_uri: edit/main/docs

docs_dir: docs

theme:
  name: material
  language: zh
  palette:
    - media: "(prefers-color-scheme: light)"
      scheme: default
      primary: white
      accent: blue
      toggle:
        icon: material/weather-night
        name: 切换深色
    - media: "(prefers-color-scheme: dark)"
      scheme: slate
      primary: black
      accent: blue
      toggle:
        icon: material/weather-sunny
        name: 切换浅色
  features:
    - navigation.tabs        # 顶部标签导航
    - navigation.sections    # 左侧按文件夹分区
    - navigation.indexes     # 分区标题可点进 index.md
    - navigation.top         # 回到顶部
    - toc.follow             # 右侧目录跟随滚动
    - content.code.copy      # 代码块一键复制
    - search.suggest
    - search.highlight

plugins:
  - search
  - roamlinks
  - git-revision-date-localized:
      enable_creation_date: true
      locale: zh
  - minify:
      minify_html: true
      minify_css: true
      minify_js: true
  - tags

markdown_extensions:
  - admonition
  - pymdownx.details
  - pymdownx.superfences:
      custom_fences:
        - name: mermaid
          class: mermaid
          format: !!python/name:pymdownx.superfences.fence_code_format
  - pymdownx.highlight
  - pymdownx.tasklist:
      custom_checkbox: true
  - pymdownx.arithmatex:
      generic: true
  - attr_list
  - toc:
      permalink: true
```

> 本站还做了两件进阶事，按需取用：
> 1. `font: false` + `extra_css` 引入**本地子集化中文字体**，国内访问更稳（见 `docs/stylesheets/extra.css` 与 `overrides/`）；
> 2. `hooks: [Scripts/sitemap_hook.py]` 在构建后生成 `sitemap.xml`（零第三方依赖）。

---

## 四、步骤二：内容组织与导航

```
civil_wiki/
├── docs/
│   ├── index.md              # 首页（站点根）
│   ├── 阅读与学习/
│   │   ├── index.md          # 分区首页（navigation.indexes 用）
│   │   └── git-从入门到协同实战.md
│   ├── 博客/
│   │   └── index.md
│   ├── stylesheets/extra.css
│   └── CNAME                  # 自定义域名声明（见第六步）
├── overrides/main.html
├── Scripts/sitemap_hook.py
├── requirements.txt
├── mkdocs.yml
└── .github/workflows/ci.yml
```

`nav:` 在 `mkdocs.yml` 里手动维护（删掉它 MkDocs 也会自动按文件名列，但顺序不可控）：

```yaml
nav:
  - 首页: index.md
  - 阅读与学习:
      - 阅读与学习/index.md
      - 阅读与学习/git-从入门到协同实战.md
  - 博客:
      - 博客/index.md
```

---

## 五、步骤三：首页网格卡片（导航站 / 作品集的灵魂）

`civil_nav` 和 `civil_works` 的卡片效果，靠 MkDocs Material 的 `.grid.cards` + Markdown 表格语法实现：

```markdown
## 我的站点

<div class="grid cards" markdown>

- :material-book-open-page-variant: **Wiki 知识库**
    ---
    我的学习笔记、硬件与嵌入式知识库。
    [:octicons-arrow-right-24: 访问 wiki.hanvon.top](https://wiki.hanvon.top){:target="_blank"}

- :material-bookmark-multiple: **Digest 书摘**
    ---
    读书摘录与文献笔记（建设中）。
    [:octicons-arrow-right-24: 访问 digest.hanvon.top](https://digest.hanvon.top){:target="_blank"}

</div>
```

要点：

- 外层 `<div class="grid cards" markdown>` 必须带 `markdown` 属性，里面才能用 Markdown；
- 每个卡片是「`- 图标 **标题**`」后跟 `---` 分隔线，再写描述与链接；
- 图标用 `:material-xxx:`（Material Design 图标）或 `:octicons-xxx:`（Octicons），名字去 [Material Symbols](https://pictogrammers.github.io/@mdi/font/) 查。

---

## 六、步骤四：GitHub Actions 自动部署

在仓库建 `.github/workflows/ci.yml`，以后只要 `git push` 到 `main`，GitHub 会自动构建并发布到 `gh-pages` 分支：

```yaml
name: ci

on:
  push:
    branches:
      - main

permissions:
  contents: write     # 允许 mkdocs gh-deploy 推送 gh-pages 分支

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # 拉全量历史，git-revision-date 才能取对时间

      - uses: actions/setup-python@v5
        with:
          python-version: "3.x"

      - run: echo "cache_id=$(date --utc +%V)" >> "$GITHUB_ENV"
      - uses: actions/cache@v4
        with:
          key: mkdocs-material-${{ env.cache_id }}
          path: .cache

      - run: pip install -r requirements.txt
      - run: mkdocs gh-deploy --force
```

在 GitHub 仓库 `Settings → Pages → Build and deployment → Source` 选择 **Deploy from a branch**，分支选 `gh-pages`、目录 `/ (root)`。
（因为我们用了 Actions 的 `gh-deploy`，其实 Actions 跑完会自动写好这个设置；首次也可手动确认。）

---

## 七、步骤五：自定义域名 + 免费 HTTPS

这是最容易翻车的一步，按顺序来：

**1. 在站点根放一个 `CNAME` 文件（位于 `docs/CNAME`）**

```
wiki.hanvon.top
```

> ⚠️ **大坑**：`mkdocs gh-deploy --force` 会**清空 `gh-pages` 分支**，连同之前手动加的自定义域名一起抹掉，导致 HTTPS 失效、页面回退到 `github.io`。
> **解法**：把 `CNAME` 放进 `docs/`，MkDocs 每次构建会把它复制到产物根目录一起部署，域名就再也不会丢。

**2. 在域名服务商加 DNS 记录**

对**每个子域名**加一条：

| 类型 | 主机名 | 指向 |
|---|---|---|
| `CNAME` | `wiki` | `wild-civil.github.io` |
| `CNAME` | `nav` | `wild-civil.github.io` |
| `CNAME` | `works` | `wild-civil.github.io` |
| `CNAME` | `digest` | `wild-civil.github.io` |

（`wild-civil` 换成你的 GitHub 用户名。）

**3. 在 GitHub 仓库 `Settings → Pages → Custom domain` 填入子域名**

例如 `civil_wiki` 填 `wiki.hanvon.top`。保存后 GitHub 会做 DNS 校验，校验通过即**自动签发免费 TLS 证书**（几分钟到几小时不等，期间 HTTPS 暂时打不开属正常）。

**4. 把 `mkdocs.yml` 的 `site_url` 改成自定义域名**

```yaml
site_url: https://wiki.hanvon.top/
```

否则站内资源路径和 Sitemap 还会指向 `github.io`。

---

## 八、步骤六：一套模板复制成多站点

四个站本质是**同一个脚手架的四个副本**，区别只在：

- `site_name` / `site_url` / `repo_url`；
- `docs/CNAME` 里的域名；
- `nav` 与 `docs/` 内容。

所以流程是：

1. 把 `civil_wiki` 整体复制一份，改目录名为 `civil_nav`；
2. 改上面三处配置；
3. `git init` → `git remote add origin https://github.com/wild-civil/civil_nav.git`；
4. 新建 GitHub 仓库（**Public**），在 `Settings → Pages` 设好自定义域名与 `gh-pages` 源；
5. `git push -u origin main`，坐等 Actions 部署完成。

重复即可生成 `civil_works`、`civil_digest`。每个仓库**相互独立**，互不影响。

---

## 九、我们踩过的坑（省你两小时）

1. **私有仓库 Pages 要钱**：GitHub **免费计划只有公开仓库支持 Pages**；私有仓库需要 GitHub Pro。结论——这些站都设成 **Public**。
2. **用户站点域名被继承**：`<user>.github.io` 设了自定义域名后，它的**项目页默认继承**该域名，导致 `wild-civil.github.io/civil_wiki` 跳到别的地址。解法——每个项目仓库在 `Settings → Pages` **单独设自己的 Custom domain**，`site_url` 也改成对应子域名。
3. **`gh-deploy --force` 清空自定义域名**：见第七步，`docs/CNAME` 根治。
4. **HTTPS 暂时打不开**：刚加自定义域名后证书还在签发，等几分钟到几小时自然变绿，不必慌。
5. **`navigation.tabs` vs `navigation.sections`**：tabs 是顶部横向标签（适合少量一级分类），sections 是左侧按文件夹折叠分区（适合内容多）。本站 wiki 用 sections，nav 用 tabs，按内容量选。
6. **中文搜索分词**：装 `jieba` 后 Material 自动启用，中文检索命中率明显提升。
7. **`!!python/name:` 标签报错**：`mkdocs.yml` 里 Mermaid 围栏的 `format:` 用了该标签，`yaml.safe_load` 会拒；CI 用完整 MkDocs 解析没问题，只有自己写脚本读 yml 时才需注意。

---

## 十、结语

至此，一个「Obsidian 写笔记 → push 到 GitHub → 自动构建 → 自定义域名 HTTPS 上线」的闭环就跑通了。
四个站点共用一套方法论，后续加站只是复制粘贴 + 改三处配置。

想深入某一环，可接着看：

- [域名规划与部署](../../阅读与学习/域名规划与部署.md) —— 子域名规划、DNS 与证书细节
- [Git 从入门到协同实战](../../阅读与学习/git-从入门到协同实战.md) —— 分支、`gh-pages`、协同工作流
- [static-badge 教程](../../阅读与学习/static-badge-教程.md) —— 状态徽章怎么挂

> 如果哪天你想和 `nav.wiki-power.com` 那样换成 Hugo 引擎，也完全可行——视觉效果能做得几乎一样，只是内容源与构建命令不同。需要的话我可以帮你做一版 Hugo 对照搭建笔记。

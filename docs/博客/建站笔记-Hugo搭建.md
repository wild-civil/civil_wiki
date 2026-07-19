---
title: 建站笔记：从零用 Hugo 搭一个导航站 / 作品集
date: 2026-07-19
tags:
  - 建站
  - Hugo
  - 教程
---

# 建站笔记：从零用 Hugo 搭一个导航站 / 作品集

> 我们喜欢的两个参考站 `nav.wiki-power.com` / `works.wiki-power.com` 都是 **Hugo** 搭的
> （实测 `meta generator = Hugo 0.147.7`，观感是自定义 Bootstrap 主题）。为了「几乎一致」的视觉，
> 我们把 **civil_nav / civil_works** 从 MkDocs 重写为 Hugo。这篇把 **从零搭一个 Hugo 站**
> 的完整流程、目录结构、数据驱动内容、自定义布局、本地验证与 CI 部署一次讲清。
>
> 适用场景：导航站（卡片网格）、作品集（带分类筛选）、个人主页——这类「数据驱动、不需要每页一篇 Markdown」的站，Hugo 比 MkDocs 更顺手。

---

## 一、为什么选 Hugo（而不是继续 MkDocs）

| 维度 | MkDocs Material | Hugo |
|---|---|---|
| 内容模型 | 一页一篇 Markdown | Markdown / 数据文件 / 自定义布局 都行 |
| 主题方式 | 配置驱动，改 `mkdocs.yml` | 任意主题，或自写 `layouts/` |
| 导航站 / 作品集 | 要硬写成很多页 | 数据文件驱动，天然合适 |
| 构建命令 | `mkdocs build` | `hugo` |
| 部署 | `mkdocs gh-deploy --force` → `gh-pages` | `hugo` + `actions-gh-pages` → `gh-pages` |

导航站本质是「一组链接卡片」、作品集是「一组带分类的卡片」，**没有正文 Markdown**，
用数据文件（`data/*.yaml`）+ 一个整页模板最干净。这是选 Hugo 的核心理由。

---

## 二、安装 Hugo（extended 版）

Hugo 是单文件 Go 二进制，下载即用。Pages 部署建议用 **extended** 版（支持 SCSS）：

```powershell
# 下载 extended 版（Windows 示例，版本号按需替换）
$i = "https://github.com/gohugoio/hugo/releases/download/v0.147.7/hugo_extended_0.147.7_windows-amd64.zip"
Invoke-WebRequest -Uri $i -OutFile hugo.zip
Expand-Archive hugo.zip -DestinationPath D:\tools\hugo
# 验证
D:\tools\hugo\hugo.exe version
```

> CI 里用 `peaceiris/actions-hugo@v3` 并设 `extended: true`，与本地一致，避免「本地能跑 CI 报错」。

---

## 三、最小目录结构

```
civil_nav/
├── config.toml              # baseURL / title / disableKinds / params
├── layouts/
│   └── index.html           # 整页模板：顶栏 + 分区卡片网格 + 页脚
├── static/
│   ├── css/style.css        # 自写样式（卡片网格）
│   └── CNAME                # nav.hanvon.top（自动复制到站点根）
├── data/
│   └── links.yaml           # 内容数据源：sections → items
├── content/
│   └── _index.md            # 首页占位（保证 home 存在）
└── .github/workflows/ci.yml # actions-hugo 构建 + actions-gh-pages 部署
```

**关键点**：不装任何主题，直接用 `layouts/index.html` 当整页模板，
内容全部来自 `data/links.yaml`。改链接只动数据文件，不动模板。

---

## 四、config.toml

```toml
baseURL = "https://nav.hanvon.top/"
title = "我的导航"
disableKinds = ["taxonomy", "term", "RSS"]   # 关掉默认分类页 / RSS，避免 WARN

[params]
  subtitle = "常用站点与工具导航"
  footer = "© 2026 wild-civil · Powered by Hugo"
```

- `baseURL` 必须是自定义域名，否则资源路径和 `canonical` 会指向 `github.io`。
- `disableKinds`：Hugo 默认会尝试渲染 tag/category 分类页，关掉它们避免无谓 WARN。

---

## 五、数据驱动内容（data/links.yaml）

```yaml
sections:
  - title: 我的站点
    items:
      - icon: book
        name: Wiki 知识库
        desc: 我的学习笔记、硬件与嵌入式知识库。
        url: https://wiki.hanvon.top
  - title: 友链
    items:
      - icon: link
        name: Power's Wiki
        desc: 参考站，Hugo 搭的。
        url: https://wiki-power.com
  - title: 常用工具
    items:
      - icon: github
        name: GitHub
        desc: 代码仓库。
        url: https://github.com/wild-civil
```

---

## 六、整页模板（layouts/index.html 片段）

用 Go 模板遍历数据渲染卡片。图标走 FontAwesome CDN（运行时加载，不影响构建）：

```go-html-template
{{ define "main" }}
<header class="topbar">
  <h1>{{ .Site.Title }}</h1>
  <p>{{ .Site.Params.subtitle }}</p>
</header>

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

<footer>{{ .Site.Params.footer }}</footer>
{{ end }}
```

FontAwesome CDN 一行引入（放在 `<head>`）：

```html
<link rel="stylesheet"
  href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css">
```

> 作品集（带分类筛选）思路一样：把数据换成 `projects.yaml`（每项带 `categories` 数组），
> 模板把类别拼成 class（`{{ delimit .categories " " }}`），再用一小段 `filterSelection()` JS
> 切换 `.show` 显隐。详见 [Hugo 对照笔记 →](建站笔记-Hugo对照.md) 第三节。

---

## 七、本地构建与验证（最重要的一步）

```bash
# 生成站点到 ./public
hugo --minify

# 起本地预览（默认 http://localhost:1313）
hugo server -D
```

**先本地验证再推远端**：直接看 `public/index.html` 和卡片是否渲染，比等 CI 报错快得多。
确认无误再 push，触发 Actions 部署。

---

## 八、CI 部署到 gh-pages

`.github/workflows/ci.yml` 核心：

```yaml
name: deploy
on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
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

部署后到 `Settings → Pages` 确认 **Source = gh-pages**（构建前就该设好，迁移也不变）。
自定义域名 `CNAME` 已经在 `static/CNAME`，Hugo 会自动拷到成品根，证书自动签发。

---

## 九、踩坑清单

1. **默认分类页 WARN** → `disableKinds = ["taxonomy","term","RSS"]`。
2. **`baseURL` 指向 github.io** → 改成自定义域名。
3. **`CNAME` 放错位置** → 放 `static/CNAME`（不是仓库根、不是 `content/`）。
4. **FontAwesome 本地化成本高** → 直接用 CDN，构建零负担。
5. **CI 用非 extended 版 hugo** → 若用 SCSS 会报错；统一 `extended: true`。
6. **没本地先验证** → 至少跑一次 `hugo --minify` 看 `public/`。
7. **项目页把 Pages Source 设成 main** → 站点 404；必须 `gh-pages`（用户页则相反，默认就是 `main` 根目录，见 [分支区别笔记 →](建站笔记-GitHubPages分支区别.md)）。

---

## 十、小结

- Hugo 搭「数据驱动」的站（导航 / 作品集）特别顺：`data/*.yaml` 存内容，`layouts/index.html` 渲染，
  改内容不动模板。
- 不依赖现成主题也能做出「几乎一致」的观感——参考站的私有主题不用克隆，自写 CSS 即可对齐。
- 部署只换「构建工具」：`hugo` + `actions-gh-pages` → `gh-pages`，Pages 设置与 MkDocs 站完全一致。

相关：

- [GitHub Pages 的 main 与 gh-pages 分支区别 →](建站笔记-GitHubPages分支区别.md)
- [Hugo 对照笔记：从 MkDocs 到 Hugo 的迁移与对比 →](建站笔记-Hugo对照.md)
- [从零搭建多站点 MkDocs（GitHub Pages + 自定义域名） →](建站教程-从零搭建多站点MkDocs.md)

# 博客 / Blog

这里记录日常的零碎观点、随笔与阶段性小结——把博客当 gist 用，不必像知识库正文那样字斟句酌。

新增的「博客改造日志」系列会记录我对本站结构、样式与工程工具的改动：

- [博客改造日志 →](博客改造日志/index.md)

也有把**搭建过程本身**写下来的实战教程：

- [从零搭建多站点 MkDocs（GitHub Pages + 自定义域名） →](建站教程-从零搭建多站点MkDocs.md)
- [Hugo 对照笔记：从 MkDocs 到 Hugo 的迁移与对比 →](建站笔记-Hugo对照.md)
- [GitHub Pages 的 main 与 gh-pages 分支区别 →](建站笔记-GitHubPages分支区别.md)
- [从零用 Hugo 搭一个导航站 / 作品集 →](建站笔记-Hugo搭建.md)
- [博客引擎的选择：MkDocs / Hugo / Hexo 怎么选（含更多平台全景） →](建站笔记-博客引擎的选择.md)

## 写作约定

- 每篇放在 `docs/博客/` 下，文件名以日期开头：`YYYY-MM-DD-标题.md`。
- 文首加 frontmatter：

  ```yaml
  ---
  title: 文章标题
  date: 2026-07-17
  tags:
    - 随笔
  ---
  ```

- 左侧导航会自动按本分区列出全部随笔，最新的在最上方。

> 示例随笔已设为 `hidden: true`，不进入公开站点导航，仅留作仓库内模板；真实随笔直接新增 `YYYY-MM-DD-*.md` 即可。

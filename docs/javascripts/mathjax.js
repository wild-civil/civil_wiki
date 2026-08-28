// 数学公式渲染配置（配合 pymdownx.arithmatex: generic 模式）
// 在页面加载/切换时重新排版公式，并做中英文间距（pangu 若启用）
// 注意：改用 SVG 输出（非 chtml），无需外部字体文件，可完全离线/本地化。
window.MathJax = {
  tex: {
    inlineMath: [["$", "$"], ["\\(", "\\)"]],
    displayMath: [["$$", "$$"], ["\\[", "\\]"]],
    processEscapes: true,
    processEnvironments: true,
    // tex-mml-svg.js 本地版不带 boldsymbol 扩展（会懒加载失败 → 整个 MathJax 崩）
    // 用宏把 \boldsymbol{xxx} 重定义为 \mathbf{xxx}，零 .md 改动搞定
    macros: { boldsymbol: ["\\mathbf{#1}", 1] }
  },
  options: {
    ignoreHtmlClass: ".*|",
    processHtmlClass: "arithmatex"
  },
  svg: {
    fontCache: "global"
  }
};

document$.subscribe(() => {
  if (window.MathJax && typeof window.MathJax.typesetPromise === "function") {
    window.MathJax.typesetPromise();
  }
});

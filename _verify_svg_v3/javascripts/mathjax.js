// 数学公式渲染配置（配合 pymdownx.arithmatex: generic 模式）
// 在页面加载/切换时重新排版公式，并做中英文间距（pangu 若启用）
// 注意：改用 SVG 输出（非 chtml），无需外部字体文件，可完全离线/本地化。
window.MathJax = {
  tex: {
    inlineMath: [["\\(", "\\)"]],
    displayMath: [["\\[", "\\]"]],
    processEscapes: true,
    processEnvironments: true
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

// 数学公式渲染配置（配合 pymdownx.arithmatex: generic 模式）
// 在页面加载/切换时重新排版公式，并做中英文间距（pangu 若启用）
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
  chtml: {
    fontURL: "https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/output/chtml/fonts/woff-v2"
  }
};

document$.subscribe(() => {
  if (window.MathJax && typeof window.MathJax.typesetPromise === "function") {
    window.MathJax.typesetPromise();
  }
});

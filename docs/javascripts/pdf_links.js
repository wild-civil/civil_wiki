// pdf_links.js —— 让所有指向 .pdf 的链接在新标签页打开（target=_blank）
// 适用: 站内 assets/ 下的讲义 PDF 在线预览、任何外链 PDF
// 实现: 监听 Material 主题的 document$ 事件（每次页面导航/渲染后执行），
//       给所有 href 以 .pdf 结尾的 <a> 加 target=_blank + rel=noopener。
document$.subscribe(() => {
  document.querySelectorAll('a[href$=".pdf"]').forEach((a) => {
    a.setAttribute('target', '_blank');
    a.setAttribute('rel', 'noopener');
  });
});

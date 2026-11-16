/* ==========================================================================
   Blender Shortcuts —— 复刻版交互
   原作：Hollis Brown, https://hollisbrown.github.io/blendershortcuts/ (GPL-3.0)
   本文件已重写：
     · 移除原作中引用不存在元素的死代码（toggleMenu / filterByTag 等）
     · 修复 toggleAllContent 末尾的 ReferenceError
     · 视频改为进入视口才加载并播放（原作 48 路 autoplay 同屏）
     · 增加亮/暗/跟随系统 三态主题
     · 增加「中文概括」总开关（默认关闭，状态存 localStorage）
     · 支持深链接（#Move 之类）自动展开对应卡片
   ========================================================================== */

(function () {
  'use strict';

  var root = document.documentElement;
  var THEME_KEY = 'blendershortcuts-theme';
  var MODES = ['auto', 'light', 'dark'];
  var MODE_LABEL = { auto: '跟随系统', light: '亮色', dark: '暗色' };

  /* ---------------- 主题 ---------------- */

  function systemIsDark() {
    return window.matchMedia &&
           window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function readMode() {
    try {
      var v = localStorage.getItem(THEME_KEY);
      return MODES.indexOf(v) >= 0 ? v : 'auto';
    } catch (e) {
      return 'auto';
    }
  }

  function paint(mode) {
    var actual = mode === 'auto' ? (systemIsDark() ? 'dark' : 'light') : mode;
    root.setAttribute('data-theme', actual);
    root.setAttribute('data-theme-mode', mode);

    var btn = document.getElementById('btnTheme');
    if (btn) {
      btn.textContent = MODE_LABEL[mode];
      btn.setAttribute('aria-label', '当前主题：' + MODE_LABEL[mode] + '，点击切换');
    }
  }

  function setMode(mode) {
    paint(mode);
    try { localStorage.setItem(THEME_KEY, mode); } catch (e) {}
  }

  function cycleTheme() {
    var cur = root.getAttribute('data-theme-mode') || 'auto';
    setMode(MODES[(MODES.indexOf(cur) + 1) % MODES.length]);
  }

  /* ---------------- 视频懒加载 ---------------- */

  function setupLazyVideo() {
    var videos = Array.prototype.slice.call(
      document.querySelectorAll('video[data-src]')
    );
    if (!videos.length) return;

    function load(v) {
      if (!v.src && v.dataset.src) v.src = v.dataset.src;
    }
    function play(v) {
      load(v);
      var p = v.play();
      if (p && typeof p.catch === 'function') p.catch(function () {});
    }

    if (!('IntersectionObserver' in window)) {
      videos.forEach(play);
      return;
    }

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) play(entry.target);
        else if (!entry.target.paused) entry.target.pause();
      });
    }, { rootMargin: '240px 0px', threshold: 0.01 });

    videos.forEach(function (v) { io.observe(v); });

    document.addEventListener('visibilitychange', function () {
      if (document.hidden) {
        videos.forEach(function (v) { if (!v.paused) v.pause(); });
      }
    });
  }

  /* ---------------- 中文概括开关 ---------------- */

  function setupZh() {
    var btn = document.getElementById('btnZh');
    if (!btn) return;
    var ZH_KEY = 'blendershortcuts-zh';

    function paint(on) {
      root.setAttribute('data-zh', on ? 'on' : 'off');
      btn.textContent = on ? '中文概括：开' : '中文概括';
      btn.setAttribute('aria-pressed', String(on));
      btn.classList.toggle('is-on', on);
    }

    var on = root.getAttribute('data-zh') === 'on';
    paint(on);

    btn.addEventListener('click', function () {
      on = !on;
      paint(on);
      try { localStorage.setItem(ZH_KEY, on ? 'on' : 'off'); } catch (e) {}
    });
  }

  /* ---------------- 全部折叠 / 展开 ---------------- */

  function setupCollapse() {
    var btn = document.getElementById('btnCollapse');
    if (!btn) return;

    var collapsed = false;

    btn.addEventListener('click', function () {
      collapsed = !collapsed;
      Array.prototype.forEach.call(
        document.querySelectorAll('.content'),
        function (c) { c.classList.toggle('is-hidden', collapsed); }
      );
      btn.textContent = collapsed ? '展开全部' : '收起全部';
      btn.setAttribute('aria-expanded', String(!collapsed));
    });
  }

  /* ---------------- 深链接定位 ---------------- */

  function revealTarget() {
    var id = location.hash.slice(1);
    if (!id) return;
    var el = document.getElementById(id);
    if (!el) return;
    var content = el.querySelector('.content');
    if (content) content.classList.remove('is-hidden');
    el.scrollIntoView({ block: 'start' });
  }

  /* ---------------- 启动 ---------------- */

  function init() {
    paint(readMode());

    var themeBtn = document.getElementById('btnTheme');
    if (themeBtn) themeBtn.addEventListener('click', cycleTheme);

    // 系统主题变化时，仅在「跟随系统」模式下重绘
    if (window.matchMedia) {
      var mq = window.matchMedia('(prefers-color-scheme: dark)');
      var onChange = function () {
        if ((root.getAttribute('data-theme-mode') || 'auto') === 'auto') paint('auto');
      };
      if (mq.addEventListener) mq.addEventListener('change', onChange);
      else if (mq.addListener) mq.addListener(onChange);
    }

    setupLazyVideo();
    setupZh();
    setupCollapse();
    revealTarget();
    window.addEventListener('hashchange', revealTarget);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

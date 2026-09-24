// nav_fold_memory.js —— 记住用户在左侧导航里手动展开/收起的「分组」，
// 直到用户切换到别的大组（顶部 tab / 顶层分类）才恢复默认。
//
// ══════════════ 为什么要有「CSS 提前量」这一层 ══════════════
// 最初只做了 JS 版：在 Material 渲染完之后用 document$ 回调覆写 checked。
// 实测时序（headless 探针）：
//    113ms  Material 用默认状态渲染完（该收起的分组是展开的）
//    124ms  document$ 触发，我的脚本才把它改成收起
// → 用户看到「先展开、再"啪"地收起」的抖动。每点一次导航都抖一次。
//
// 根因：**JS 只能在渲染后纠正，而 CSS 在首次绘制前就生效**。
// 正解：把记忆状态**提前写进 CSS**，让浏览器第一帧就按记忆渲染。
// 具体做法：JS 每次记录状态时，同步维护一个 <style> 标签，把「要收起的分组」
// 用结构选择器写进去。下次导航时浏览器解析到这段 CSS 就已经是折叠态，零跳变。
//
// ══════════════ 为什么选择器要写成「结构路径」 ══════════════
// Material 给分组开关的 id 是 __nav_4 / __nav_4_2 / __nav_5 / __nav_5_2……
// 这个编号**会随当前页面深度整体平移**（嵌软首页是 __nav_4_2，深一级变 __nav_5_2），
// 所以 CSS 里**不能**写死 #__nav_4_2 —— 换页就失效。
// 解法：改用「顶层第 i 个分组 > 它的第 j 个子分组 > …」的**结构路径**表达，
// 用 :nth-of-type 逐级定位。结构路径与页面深度无关（目录树长什么样就长什么样），
// 因此跨页稳定。这正是 JS 侧 normalizeId() 做的同一件事，只是搬到 CSS 里。
//
// 依赖：Material 的 document$ 事件（每次页面导航/渲染后触发）。
//       :has() 只用于「JS 未跑时也不误伤」，主选择器是 :nth-of-type 结构路径（兼容性更好）。

(() => {
  const STORE_PREFIX = 'navfold:';
  const STYLE_ID = 'nav-fold-memory-style';
  // 顶层大组数量有限，且本脚本只在「顶层 li」上打标记，故用一个稳定属性名即可。
  const TOP_ATTR = 'data-nav-top';

  // ── 站点根 ──────────────────────────────────────────────
  // 只有站点部署在子路径（如 /repo/）时才需要剥前缀。本站在域名根，故默认 '/'。
  // 不用 canonical：它写的是线上域名，本地预览时会推出错误的根。
  function siteRoot() {
    return '/';
  }

  // ── 顶层大组标识（= 记忆分区 key）───────────────────────
  // 关键：**key 必须能在「首帧前」算出来**，否则无法消除闪烁。
  // 原因：消除闪烁靠的是 overrides/main.html 里内联的 <style> 提前量脚本，
  //       而那个脚本在 <head> 里同步执行 —— 此时 DOM 还没解析，拿不到 tab 文字。
  //       唯一两边都能算、且算得出同一个值的东西 = **URL 首段**。
  // 事实支撑：docs/ 下的顶层目录名与 nav 顶层分组名一一对应
  //       （工作与项目 / 技术与编程 / 嵌入式 / 阅读与学习 / 生活与兴趣 / 杂记），
  //       所以「URL 首段」== 运行时看到的「顶层分组名」。
  // 细节：pathname 里是非 ASCII 时是百分号编码的，须 decodeURIComponent 归一。
  // 边界：站点根页（README.md → `/`）没有首段 → 'home'，单页无分组，记忆本就不参与。
  function currentTab() {
    const segs = location.pathname.split('/').filter(Boolean);
    return segs.length ? decodeURIComponent(segs[0]) : 'home';
  }

  function storeKey() {
    return STORE_PREFIX + currentTab();
  }

  function loadState() {
    try {
      return JSON.parse(localStorage.getItem(storeKey()) || '{}');
    } catch (e) {
      return {};
    }
  }

  function saveState(state) {
    try {
      localStorage.setItem(storeKey(), JSON.stringify(state));
    } catch (e) {
      /* localStorage 不可用时静默降级为「不记忆」 */
    }
  }

  // ── 把 __nav_N 归一化成与深度无关的结构键 ───────────────
  // 顶层 __nav_4 → n4；其内部的 __nav_4_2 → n4.2；再深一层 → n4.2.1
  function normalizeId(id) {
    if (!id) return null;
    const rest = id.replace(/^__nav_/, '');
    const parts = rest.split('_').filter(Boolean);
    if (!parts.length) return null;
    return 'n' + parts.join('.');
  }

  // 结构键 → CSS 结构选择器（与页面深度无关）
  //   n4.2 → 「左栏顶层 ul 的第 4 个 li」>「其 nav 里 ul 的第 2 个 li」
  // ⚠️ 第一层必须用 `.md-sidebar--primary nav.md-nav--primary > ul.md-nav__list`
  //    直接子选择器锚定。早期写成 `.md-sidebar--primary ul.md-nav__list`（无 >），
  //    会命中 sidebar 里**所有**层级的 ul → 一条规则匹配到 5 个跨分组的 li，
  //    既误伤别的大组、又让「首帧提前量」形同虚设。
  // 用 :nth-of-type 而非 :nth-child：nav 列表里会穿插 label.md-nav__title 等非 li 节点。
  function keyToSelector(key) {
    const parts = key.replace(/^n/, '').split('.').filter(Boolean);
    if (!parts.length) return null;
    let sel = '.md-sidebar--primary nav.md-nav--primary > ul.md-nav__list';
    parts.forEach((p, i) => {
      const n = parseInt(p, 10);
      if (!n || n < 1) return;
      sel += (i === 0 ? '' : ' > nav.md-nav > ul.md-nav__list') + ` > li.md-nav__item:nth-of-type(${n})`;
    });
    return sel;
  }

  function navRoot() {
    return document.querySelector('.md-sidebar--primary nav.md-nav--primary') ||
           document.querySelector('.md-sidebar--primary');
  }

  // 给顶层分组 li 打上「大组名」标记，用于二次校验（离开该大组即失效）。
  function tagTopLevels(root) {
    const list = root ? root.querySelector('ul.md-nav__list') : null;
    if (!list) return;
    [...list.children].forEach((li) => {
      if (li.tagName !== 'LI') return;
      const toggle = li.querySelector(':scope > input.md-nav__toggle');
      if (!toggle) return;
      const link = li.querySelector(':scope > .md-nav__link, :scope > a.md-nav__link');
      li.setAttribute(TOP_ATTR, (link ? link.textContent.trim() : '') + '#' + normalizeId(toggle.id));
    });
  }

  function navToggles() {
    return [...document.querySelectorAll(
      '.md-sidebar--primary input.md-nav__toggle[id^="__nav_"]'
    )];
  }

  // 判断某个 toggle 是否位于「与记忆同一个大组」内。
  // ⚠️ 比较的是「顶层前缀」，不是相等（踩过这个坑，详见 memory）。
  function inSameTopGroup(input, key) {
    let p = input.parentElement;
    while (p && !p.hasAttribute(TOP_ATTR)) p = p.parentElement;
    if (!p) return true;
    const memo = (p.getAttribute(TOP_ATTR) || '').split('#')[1];
    if (!memo) return true;
    return key.split('.')[0] === memo.split('.')[0];
  }

  // ── 把「收起」的键写成 CSS（这是消除闪烁的关键）──────────
  // 每条规则折叠「该分组的嵌套 nav」，并同步隐藏它的折叠箭头状态由原生 checkbox 负责。
  // 注意：只写「收起」的规则。展开是 Material 默认行为，不需要 CSS 干预——
  //       少写一半规则，也避免和 Material 的 active-path 展开逻辑打架。
  function writeStyle(state) {
    let el = document.getElementById(STYLE_ID);
    if (!el) {
      el = document.createElement('style');
      el.id = STYLE_ID;
      document.head.appendChild(el);
    }
    const rules = [];
    Object.keys(state).forEach((k) => {
      if (state[k] === false) {
        const sel = keyToSelector(k);
        if (sel) rules.push(`${sel} > nav.md-nav { display: none !important; }`);
      }
    });
    el.textContent = rules.join('\n');
  }

  // 结构键 → 归一化前缀，用于「CSS 里的规则是否属于当前大组」判断
  function stateKeysForCurrentTab() {
    const state = loadState();
    return state;
  }

  function apply() {
    const root = navRoot();
    if (!root) return;
    tagTopLevels(root);
    const state = loadState();
    navToggles().forEach((input) => {
      const key = normalizeId(input.id);
      if (!key || !Object.prototype.hasOwnProperty.call(state, key)) return;
      if (!inSameTopGroup(input, key)) return;
      input.checked = !!state[key];
      const li = input.closest('.md-nav__item');
      if (li) li.setAttribute('aria-expanded', String(!!state[key]));
    });
    // 关键：把记忆同步成 CSS，供「下次导航时首帧直接正确」
    writeStyle(state);
  }

  function bind() {
    navToggles().forEach((input) => {
      if (input.dataset.navFoldBound === '1') return;
      input.dataset.navFoldBound = '1';
      input.addEventListener('change', () => {
        const key = normalizeId(input.id);
        if (!key) return;
        if (!inSameTopGroup(input, key)) return;
        const state = loadState();
        state[key] = input.checked;
        saveState(state);
        // 立即更新 CSS，保证后续导航首帧正确
        writeStyle(state);
      });
    });
  }

  // ── 启动时机 ──────────────────────────────────────────
  // 【首帧提前量由 overrides/main.html 里的内联 <script> 负责】——不要再在这里抢跑。
  // 血泪教训：extra_javascript 是 defer 加载的，实测要 ~180ms 才执行，
  //           而 Material 首帧 ~110ms 就画完了。所以本文件里任何"尽早"都是假的，
  //           以前那段 `if (document.head) writeStyle(...)` 根本没赶在首帧前。
  //           真正的提前量必须内联在 <head>（见 overrides/main.html）。
  // 本文件只负责：① 交互时（用户手动折叠/展开）更新记忆 + 刷新那份 CSS；
  //              ② SPA 导航后把 checked 同步成记忆值（视觉上已由 CSS 保证不闪）。
  // 注：SPA 页内导航不会重新执行 <head> 内联脚本，但 apply() 末尾会重写 style，
  //     且此时不存在"首帧"问题（DOM 已在内存里，改 style 立即生效、无重绘跳变）。

  // 每次渲染后：先绑定事件，再套用记忆状态（并同步 CSS）。
  if (typeof document$ !== 'undefined' && document$.subscribe) {
    document$.subscribe(() => {
      bind();
      apply();
    });
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      bind();
      apply();
    });
  }

  // 顶部 tab 切换（同页内可能不触发 document$，如锚点跳转）时重算一次。
  window.addEventListener('hashchange', apply);
})();

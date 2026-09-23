// nav_fold_memory.js —— 记住用户在左侧导航里手动展开/收起的「分组」，
// 直到用户切换到别的大组（顶部 tab / 顶层分类）才恢复默认。
//
// 设计要点：
//  1. Material 每次跳转都由服务端重新渲染 checked（按「当前页是否在该组内」），
//     本身不记忆用户的临时展开/收起。本脚本在每次渲染后用 localStorage 覆写。
//  2. 记忆按「顶层大组」分区存储：key 形如 `navfold:<tab>`，切 tab 时读到的是
//     另一套（或空）记录 → 达到「切大组即恢复默认」的效果。
//  3. 只记录用户「亲自点过」的分组；没点过的分组完全交给 Material 默认逻辑，
//     避免破坏「激活路径自动展开」。
//
// 依赖：Material 的 document$ 事件（每次页面导航/渲染后触发）。

(() => {
  const STORE_PREFIX = 'navfold:';
  // 顶层大组数量有限，且本脚本只在「顶层 li」上打标记，故用一个稳定属性名即可。
  const TOP_ATTR = 'data-nav-top';

  // ── 站点根 ──────────────────────────────────────────────
  // 只有站点部署在子路径（如 /repo/）时才需要剥前缀。本站在域名根，故默认 '/'。
  // 不用 canonical：它写的是线上域名，本地预览时会推出错误的根。
  function siteRoot() {
    return '/';
  }

  // ── 顶层大组标识（= 记忆分区 key）───────────────────────
  // 关键：**不能**用顶部 tab 的 href 取段。
  //   Material 的 tab href 指向该分组的「落地页」，而不等于分组名：
  //   「嵌入式」这个 tab 的 href 是 `../../../硬件与半导体/`（它的 index 页在硬件与半导体目录下），
  //   取段会得到 `硬件与半导体`。
  // 正解：用 **tab 的文字标签**（就是 nav 第一层的分组标题，与目录无关，稳定）。
  // 取不到文字时，退回「左栏第一个顶层分组的链接文字」（同一来源）。
  function currentTabFromNav() {
    // 最稳：左栏顶层分组的链接文字 —— 它一定等于 nav 里那条顶层分组标题
    const firstTop = document.querySelector('.md-sidebar--primary ul.md-nav__list > li.md-nav__item > .md-nav__link');
    if (firstTop) {
      const t = firstTop.textContent.trim();
      if (t) return t;
    }
    return null;
  }

  function currentTab() {
    // ① 顶部 tab 的文字标签（与 nav 顶层分组同名）
    const active = document.querySelector('.md-tabs__item--active .md-tabs__link') ||
                   document.querySelector('.md-tabs__link--active');
    if (active) {
      const t = active.textContent.trim();
      if (t) return t;
    }
    // ② 左栏第一个顶层分组的文字
    const navTop = currentTabFromNav();
    if (navTop) return navTop;
    // ③ 退回当前 URL 首段
    return location.pathname.split('/').filter(Boolean)[0] || 'home';
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

  // ── 只锚定「顶层分组」的开关 ────────────────────────────
  // 同一个大组在左栏的编号会因为页面深度不同而整体平移
  // （嵌软首页是 __nav_4 / __nav_4_2，再深一级就变成 __nav_5 / __nav_5_2），
  // 所以**不能**把 __nav_N 直接当记忆键。这里把 id 归一化成「顶层序号 + 组内相对路径」：
  // 顶层的 __nav_4 → n4；其内部的 __nav_4_2 → n4.2；再深一层 → n4.2.1
  function normalizeId(id) {
    if (!id) return null;
    const rest = id.replace(/^__nav_/, '');
    const parts = rest.split('_').filter(Boolean);
    if (!parts.length) return null;
    return 'n' + parts.join('.');
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
  // ⚠️ 比较的是「顶层前缀」，不是相等：
  //      __nav_4_2 → n4.2，它所属的顶层分组标记是「嵌入式#n4」。
  //      若拿 n4.2 和 n4 做 === 必然为 false，会让所有写入被静默拒绝（踩过这个坑）。
  function inSameTopGroup(input, key) {
    let p = input.parentElement;
    while (p && !p.hasAttribute(TOP_ATTR)) p = p.parentElement;
    if (!p) return true; // 找不到标记就不限制（保守放行）
    const memo = (p.getAttribute(TOP_ATTR) || '').split('#')[1];
    if (!memo) return true;
    // key 形如 n4 / n4.2 / n4.2.1，取其顶层段与标记比较
    const keyTop = key.split('.')[0];
    const memoTop = memo.split('.')[0];
    return keyTop === memoTop;
  }

  function apply() {
    const root = navRoot();
    if (!root) return;
    tagTopLevels(root);
    const state = loadState();
    navToggles().forEach((input) => {
      const key = normalizeId(input.id);
      if (!key || !Object.prototype.hasOwnProperty.call(state, key)) return;
      // 二次校验：编号平移会让「大组 A 的 nX」撞上「大组 B 的 nX」，靠顶层标记挡掉
      if (!inSameTopGroup(input, key)) return;
      input.checked = !!state[key];
      const li = input.closest('.md-nav__item');
      if (li) li.setAttribute('aria-expanded', String(!!state[key]));
    });
  }

  function bind() {
    navToggles().forEach((input) => {
      if (input.dataset.navFoldBound === '1') return;
      input.dataset.navFoldBound = '1';
      input.addEventListener('change', () => {
        const key = normalizeId(input.id);
        if (!key) return;
        // 只在「本大组内」留记录
        if (!inSameTopGroup(input, key)) return;
        const state = loadState();
        state[key] = input.checked;
        saveState(state);
      });
    });
  }

  // 每次渲染后：先绑定事件，再套用记忆状态。
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

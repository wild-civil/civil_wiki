// nav_fold_memory.js —— 记住用户在左侧导航里手动展开/收起的「分组」，全站共享一份。
//
// ══════════════ 关于「记忆范围」的重大修正（2026-09-24）══════════════
// 【曾经的错误设计】记忆按「URL 首段」分区，并配了「切到别的大组就恢复默认」的行为。
//   前提假设是「docs 顶层目录名 == nav 顶层分组名」。这个假设在**多入口**站点上不成立。
//
// 【实测证据（headless 探针）】本站的侧栏里，**同一个 <li>** 被判成了多个分区：
//     「硬件设计与半导体」这一组，在侧栏里同时以三种前缀出现——
//         /硬件与半导体/硬件设计/…            （45 条，从「嵌硬」分组进入）
//         /EDA/嘉立创EDA/…                    （14 条，从 EDA 分组进入）
//         /嵌入式/嵌硬 · 硬件与半导体/EDA/…    （  9 条，从顶部 tab 进入）
//   三者指向同一份 HTML（mkdocs 按「从哪个入口点进来」生成不同相对路径），
//   但它们**首段不同** → 同一个分组的展开状态被劈进 navfold:硬件与半导体 / navfold:EDA /
//   navfold:嵌入式 三个互不相干的 key 里。
//   用户实际感受就是：展开「硬件设计」→ 点「显示与屏幕」的文章（URL 首段变
//   「硬件与半导体」→ 读到空 key）→ 硬件设计莫名收起；再点 EDA 的文章
//   （URL 首段变回「嵌入式」→ 读到记忆）→ 硬件设计又展开。
//
// 【现状设计】记忆**全站共享一份**，key 是常量，与 URL 完全无关。
//   · 手风琴的分组名（组内第 i 个分组）本身就是全站唯一的，天然无歧义；
//   · key 恒定 → 「多入口导致记忆分裂」这类 bug 从结构上不可能再发生；
//   · 首帧内联脚本也因此不再需要 decodeURIComponent 算分区（它本来就没有 DOM 可依赖）。
//   代价：不再「切换顶层大组自动重置」。实测本站各顶层大组下的分组名互不重叠，
//   故该差异在实际使用中无可感影响。若将来确需重置，按大组过滤即可，无需改 key 结构。
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

  // ── 记忆键：全站唯一，与 URL 无关 ───────────────────────
  // 历史教训：曾用「URL 首段」当分区键（decodeURIComponent(location.pathname.split('/')[0])），
  //   在**多入口**站点上同一分组会以不同前缀出现，导致记忆被劈成多份（详见文件头【重大修正】）。
  // 现在改为常量：整个站点共用一份分组展开状态。
  //   好处之一：首帧内联脚本（overrides/main.html）也能用同一个常量，不必依赖 DOM 或 URL。
  const TAB = 'site';
  function storeKey() {
    return STORE_PREFIX + TAB;
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

  // ══════════════ 关于「元素寻址」的重大修正（2026-09-24）══════════════
  // 【历史 bug】早期版本把 __nav_N 的编号直接当作 DOM 的 :nth-of-type 序号来拼选择器：
  //     n4.1.2 → ... > li.md-nav__item:nth-of-type(4) > nav > ul > li:nth-of-type(1)
  //                                          > nav > ul > li:nth-of-type(2)
  //   **这是错的**。Material 的 __nav_N 编号 = nav 树里的「节点序号」（从 1 开始，
  //   把「分组自己的落地页」也算作一个子节点），而 DOM 里那个落地页并不会渲染成
  //   一个独立的带 toggle 的 <li>（它被吸收为分组自身的链接）。
  //   实测（本站「嵌入式 > 嵌硬」下）：
  //         __nav_4_1_2  → 内部 ul 的第 1 个 li   （显示与屏幕）
  //         __nav_4_1_3  → 内部 ul 的第 2 个 li   （射频与天线）
  //   于是 :nth-of-type(2) 命中的是「射频与天线」而不是「显示与屏幕」——
  //   整套「首帧提前量」CSS 一直在折叠/隐藏**错误的组**（且静默无报错）。
  //
  // 【正解】不再用编号做算术。改为：**运行时遍历真实 DOM，逐级记录 :nth-of-type**，
  //   得到「验证过的选择器」，然后把这个选择器本身写进 CSS。
  //   选择器与页面深度无关（它就是真实结构路径），所以跨页仍然稳定。
  //   代价：首次记录需要 DOM 可用（apply() 时必然满足）。
  //
  //   buildSelectorFor(li)：从某分组的 <li> 向上走到 sidebar 根，逐级数 :nth-of-type。
  function buildSelectorFor(li) {
    if (!li) return null;
    const anchor = document.querySelector('.md-sidebar--primary nav.md-nav--primary');
    if (!anchor || !anchor.contains(li)) return null;
    const chain = [];
    let cur = li;
    while (cur && cur !== anchor) {
      if (cur.tagName === 'LI' && cur.classList.contains('md-nav__item')) {
        const parent = cur.parentElement;
        let n = 0;
        for (const sib of parent.children) {
          if (sib.tagName !== 'LI' || !sib.classList.contains('md-nav__item')) continue;
          n += 1;
          if (sib === cur) break;
        }
        chain.unshift(n);
      }
      cur = cur.parentElement;
    }
    if (!chain.length) return null;
    // 顶层用「nav.md-nav--primary 的 ul.md-nav__list」锚定，其余层用「父 li > nav > ul」
    let sel = '.md-sidebar--primary nav.md-nav--primary > ul.md-nav__list';
    chain.forEach((n, i) => {
      sel += (i === 0 ? '' : ' > nav.md-nav > ul.md-nav__list') +
             ` > li.md-nav__item:nth-of-type(${n})`;
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

  // ── 把记忆写成 CSS（这是消除闪烁的关键）────────────────
  // 两个方向都要写：
  //   · 收起（state=false）：display:none，让首帧就不显示这个分组
  //   · 展开（state=true） ：强制展开 + transition:none。
  //     为什么必须写「展开」？非激活路径上的分组在 Material 里默认收起；
  //     若首帧脚本不表态，观感就是「先收起、再被 JS 改 checked 后动画展开」——
  //     那 .25s 过渡正是山哥看到的「折叠再展开」。transition:none 用于掐掉它。
  // 属性集取自实测（桌面 grid 布局 / 窄屏 flex 布局，两者通用）：
  //   grid-template-rows → 桌面展开所需；transform:none → 窄屏展开所需；互不干扰。
  // 选择器一律由 buildSelectorFor() 从真实 DOM 走出（见上文【重大修正】），
  // 不再对 __nav_N 编号做任何算术。
  function writeStyle(state) {
    let el = document.getElementById(STYLE_ID);
    if (!el) {
      el = document.createElement('style');
      el.id = STYLE_ID;
      document.head.appendChild(el);
    }
    const rules = [];
    navToggles().forEach((input) => {
      const key = normalizeId(input.id);
      if (!key || !Object.prototype.hasOwnProperty.call(state, key)) return;
      if (!inSameTopGroup(input, key)) return;
      const li = input.closest('li.md-nav__item');
      const sel = buildSelectorFor(li);
      if (!sel) return;
      if (state[key] === false) {
        rules.push(`${sel} > nav.md-nav { display: none !important; }`);
      } else {
        rules.push(
          `${sel} > nav.md-nav { grid-template-rows: minmax(.4rem, 1fr) !important;` +
          ` opacity: 1 !important; visibility: visible !important;` +
          ` transform: none !important; transition: none !important; }`
        );
        rules.push(`${sel} > nav.md-nav > .md-nav__list { overflow: visible !important; }`);
      }
    });
    el.textContent = rules.join('\n');
  }

  // ── 持久化「验证过的选择器」，供 overrides/main.html 首帧脚本重放 ────────
  // 首帧脚本在 <head> 同步执行，DOM 尚不存在，无法现场走树；
  // 因此这里把走树得到的**选择器字符串**存下来，首帧原样重放，零算术。
  const SEL_PREFIX = 'navfold-sel:';
  function selStoreKey() {
    return SEL_PREFIX + TAB;
  }
  function loadSelMap() {
    try {
      return JSON.parse(localStorage.getItem(selStoreKey()) || '{}');
    } catch (e) {
      return {};
    }
  }
  function saveSelMap(m) {
    try {
      localStorage.setItem(selStoreKey(), JSON.stringify(m));
    } catch (e) {
      /* 静默降级 */
    }
  }
  function persistSelectors(state) {
    const map = loadSelMap();
    let dirty = false;
    navToggles().forEach((input) => {
      const key = normalizeId(input.id);
      if (!key || !Object.prototype.hasOwnProperty.call(state, key)) return;
      if (!inSameTopGroup(input, key)) return;
      const li = input.closest('li.md-nav__item');
      const sel = buildSelectorFor(li);
      if (!sel) return;
      if (map[key] !== sel) {
        map[key] = sel;
        dirty = true;
      }
    });
    if (dirty) saveSelMap(map);
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
    // 并把「本次走树得到的、已验证的选择器」持久化，供 <head> 首帧脚本原样重放
    persistSelectors(state);
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
        // 立即更新 CSS + 选择器存储，保证后续导航首帧正确
        writeStyle(state);
        persistSelectors(state);
      });
    });
  }

  // ══════════════ 抑制「导航后的侧栏跟随滚动」 ══════════════
  // 现象：在同一大组内换文章（如「汽车电子/无钥匙进入系统」→「显示与屏幕/屏幕接口与带宽」）
  //       时，左栏内容会整体动一下，观感像「先折叠、再展开」。
  //
  // 真凶（读 Material bundle 的 lo() 函数，非猜测）：
  //   Material 每次布局刷新后，会把「当前激活的导航项」滚到侧栏可见区中央：
  //       for (let l of M(".md-nav__link--active[href]", e)) {
  //         f.scrollTo({ top: (l.offsetTop - f.offsetTop) - f.clientHeight / 2 })
  //       }
  //   实测时序（headless 探针）：
  //       t=367ms  document$ 触发（Material SPA 导航完成）
  //       t=370ms  scrollTo({top: 18})   ← 就在 document$ 之后 3ms
  //       t=394ms  scrollTop 停在 8      ← 容器最多只能滚 8px（scrollH 134 - clientH 126）
  //   也就是「想滚 18px，但只滚得动 8px」——这 8px 的位移就是用户看到的那一下。
  //
  // 为什么本站更容易触发：docs 里每个 `nav.md-nav` 底部都有 -0.4rem 的负边距配套，
  // 使分组内容的溢出量**恰好是 8px**（实测「汽车电子」「惯性导航」两组都是 overflow=8）。
  // 8px 的溢出本不该滚动（激活项完全看得见），Material 却仍会滚这一下 → 纯视觉噪声。
  //
  // 修法：只在「这次滚动没有实际必要」时吞掉它，而不是一刀切禁用。
  //   · 必要 = 激活项确实可能在视野外（容器可滚动量明显大于噪声量）
  //   · 不必要 = 可滚动量 ≤ NOISE_MAX（8px 级别的零头），激活项必然可见
  // 判据用「容器的最大可滚动量」而非「本次滚动目标值」——因为后者依赖激活项位置，
  // 而前者直接反映「这个侧栏到底需不需要跟随滚动」，语义更稳。
  //
  // 安全性：只重写 scrollwrap 实例的 scrollTo，且只吞「对象参数 + 有 top」的调用形态。
  //   · 用户滚轮/触摸拖动不经过 scrollTo → 不受影响
  //   · 带 element 参数（scrollIntoView 语义）或 left/top 位置参数 → 原样放行
  //   · 容器换了（SPA 重建 DOM）→ 每次 apply() 重新打补丁，用标记防重复
  const NOISE_MAX = 24; // px：可滚动量小于此值视为「零头噪声」，抑制跟随滚动
  function tameSidebarScroll() {
    const wrap = document.querySelector('.md-sidebar--primary .md-sidebar__scrollwrap');
    if (!wrap || wrap.__scrollTamed) return;
    wrap.__scrollTamed = true;
    const orig = wrap.scrollTo.bind(wrap);
    wrap.scrollTo = function (...args) {
      const o = args[0];
      if (o && typeof o === 'object' && typeof o.top === 'number' && args.length === 1) {
        const maxScroll = wrap.scrollHeight - wrap.clientHeight;
        if (maxScroll <= NOISE_MAX) return; // 零头噪声：不滚，激活项本来就在视野内
      }
      return orig(...args);
    };
  }

  // ── 启动时机 ──────────────────────────────────────────
  // 【首帧提前量由 overrides/main.html 里的内联 <script> 负责】——不要再在这里抢跑。
  // 血泪教训：extra_javascript 是 defer 加载的，实测要 ~180ms 才执行，
  //           而 Material 首帧 ~110ms 就画完了。所以本文件里任何"尽早"都是假的，
  //           以前那段 `if (document.head) writeStyle(...)` 根本没赶在首帧前。
  //           真正的提前量必须内联在 <head>（见 overrides/main.html）。
  // 本文件只负责：① 交互时（用户手动折叠/展开）更新记忆 + 刷新那份 CSS；
  //              ② SPA 导航后把 checked 同步成记忆值（视觉上已由 CSS 保证不闪）；
  //              ③ 抑制「导航后的侧栏跟随滚动」（见 tameSidebarScroll）。
  // 注：SPA 页内导航不会重新执行 <head> 内联脚本，但 apply() 末尾会重写 style，
  //     且此时不存在"首帧"问题（DOM 已在内存里，改 style 立即生效、无重绘跳变）。

  // 每次渲染后：先绑定事件，再套用记忆状态（并同步 CSS），最后处理跟随滚动。
  function afterRender() {
    bind();
    apply();
    tameSidebarScroll();
  }

  if (typeof document$ !== 'undefined' && document$.subscribe) {
    document$.subscribe(afterRender);
  } else {
    document.addEventListener('DOMContentLoaded', afterRender);
  }

  // 首次进入页面（非 SPA）时也要打上补丁：document$ 在初次加载时也会触发，
  // 但为防 Material 版本差异导致首屏不触发，补一次 DOMContentLoaded 兜底（幂等）。
  if (typeof document$ !== 'undefined' && document$.subscribe) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', tameSidebarScroll);
    } else {
      tameSidebarScroll();
    }
  }

  // 顶部 tab 切换（同页内可能不触发 document$，如锚点跳转）时重算一次。
  window.addEventListener('hashchange', afterRender);
})();

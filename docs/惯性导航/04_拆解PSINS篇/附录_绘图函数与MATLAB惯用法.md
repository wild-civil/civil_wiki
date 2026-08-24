---
category: 惯性导航
tags: [MOC, 导航, 惯导, MATLAB, 绘图, 科普, 附录]
---

# 绘图函数与 MATLAB 惯用法速查（附录）

> 本页是「拆解 PSINS 篇」配套绘图代码的**字典页**。
> 代码文件（`assets/` 下的 `miniinsplot.m` / `miniavpcmpplot.m` / `miniinsplot3d.m`，及其 Python 镜像 `miniplot.py`）本身只写了**轻量注释**，所有函数签名、参数含义、以及那些"眼生的 MATLAB 写法"都集中放在这里讲透。
> **看不懂某段 `.m` 代码时，先来这一页查。** 新人友好，尽量不假设你熟悉 MATLAB。

## 0. 先建立两个认知

1. **这些绘图函数不是 wiki 正文代码**，而是「迷你 PSINS」的**可视化模块**——用来把 P1/P2/P3 的数值结果画成图。它们最重要的属性是"和 Python 版逐数字对齐"，而不是"让初学者一眼看懂"。
2. **你之前觉得看不懂，80% 是词汇问题，不是代码坏**。里面那些 `scrsz`、`figure(...)`、`nargin`、`varargin` 全是 MATLAB 标准 idiom（惯用法），每个 MATLAB 函数为支持"多种调用方式"都得这么写。看懂下面第 2 节的词典，三个文件就通了。

---

## 1. 三个绘图函数速查

> 通用数据约定（三个函数都用）：传入的 `avp` / `trj` / `dr` 都是 **N×10 矩阵**，列含义如下（与 PSINS 的 `avp` 一致）：
>
> | 列 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
> |---|---|---|---|---|---|---|---|---|---|---|
> | 含义 | pitch | roll | yaw | Ve | Vn | Vu | lat | lon | h | t |
> | 单位 | rad | rad | rad | m/s | m/s | m/s | rad | rad | m | s |
>
> 所有角度在矩阵里是**弧度**；画图时才 `./deg` 转成度。

### 1.1 `miniinsplot` —— 6 子图状态 + 轨迹

来源对齐：PSINS 的 `insplot(avp,'avp')`（自写零依赖，不调用 `glv`/`myfigure`/`xygo`/`pos2dxyz`）。

**三种调用模式**（靠「传了几个参数 + 第几个是字符串」自动区分，见第 2.1 节）：

```matlab
% 模式 A：单轨迹（画一条解算自己的 6 子图）
miniinsplot(avp, ttl)
%   avp : N×10 解算结果
%   ttl : 字符串，作为输出文件名后缀 -> 生成 miniinsplot_<ttl>.png

% 模式 B：对比（单解算 vs 真值）
miniinsplot(dr, truth, ttl)
%   dr    : N×10 解算结果（红）
%   truth : N×10 真值（黑，参考基准）
%   轨迹子图叠加：黑(真值) + 红(估计) + 红星(起点)

% 模式 C：对比（多解算 vs 真值）
miniinsplot({s1, s2, ...}, truth, ttl, labels)
%   {s1,s2,...} : cell 数组，每个元素是一个 N×10 解算
%   truth       : N×10 真值（黑）
%   ttl          : 文件名后缀
%   labels       : 可选 cell 字符串，自定义图例；不传则自动推断
```

**6 个子图布局**（`subplot(3,2,k)` 表示 3 行 2 列的第 k 格）：

| 位置 | 内容 |
|---|---|
| (3,2,1) | Pitch / Roll（随时间） |
| (3,2,2) | Yaw |
| (3,2,3) | Velocity（VE / VN / VU / VG 地速） |
| **(3,2,[4,6])** | **轨迹（E 右 / N 上）**——第 4、6 格合并成底部一大块 |
| (3,2,5) | Position offset from start（Dlat / Dlon / DH） |

> 第 5 格的 **DH 绿线**就是看 `free` vs `fix` 垂直差异的地方（见 P2）。

### 1.2 `miniavpcmpplot` —— 误差曲线对比

来源对齐：PSINS 的 `avpcmpplot(avp0, varargin)` 的 `'avp'` 6 面板。

```matlab
miniavpcmpplot(trj, avps, names)
%   trj   : N×10 真值（100 Hz）
%   avps  : cell 数组，每个元素是一个解算的 N×10（50 Hz，双子样）
%   names : cell 字符串，每个解算一个图例名
```

**6 面板**：(1) 姿态（真值黑实线 + 各解算彩色虚线）、(2) 姿态误差(arcsec)、(3) 速度、(4) 速度误差、(5) 位置偏移(Dlat/Dlon/DH)、(6) 位置误差(dN/dE/dH)。每面板标题带 RMS。

解算配色/线型固定循环：`sol_color = {'b','r','g','m','c'}`、`sol_style = {'--','-.',':','-'}`（free=蓝虚线、fix=红点划线…）。

### 1.3 `miniinsplot3d` —— 3D 轨迹对比（PSINS 无此图，属自写增强）

```matlab
% 模式 A：单轨迹
miniinsplot3d(avp, ttl)
%   Z = (高度 - 起点高度) × ZFAC

% 模式 B：对比（多解算 vs 真值）
miniinsplot3d({s1, s2, ...}, truth, ttl, labels)
%   真值画黑线、贴在 Z=0 参考平面
%   解算的 Z = (估计高度 - 同时间戳真值高度) × ZFAC
```

**关键参数 `ZFAC = 8.0`**：Z 轴放大倍数（**仅为显示放大，单位仍是 m**）。原因：本场景水平跨度 ~6000 m，而垂直误差最多才 ~580 m，真比例下 3D 会变成"摊平的煎饼"，free 的抬升肉眼看不见；放大 8 倍后才明显。标题会标注 `×8`。

用途：专门把"垂直通道开环发散"立起来——free 轨迹明显抬离 truth 平面、fix 紧贴地面（详见 P2）。

### 1.4 三个函数的通用约定

| 约定 | 说明 |
|---|---|
| **真值永远黑线** | `truth` 一律 `'k-'`、线宽 1.8，作为参考基准 |
| **解算按配色循环** | `solcols = {'r-','b-','g-','m-','c-'}`；当传 2 个解算时即 free=红、fix=蓝 |
| **坐标朝向** | East = `(lon-lon0)*Re*cos(lat0)`（横轴/右），North = `(lat-lat0)*Re`（纵轴/上），标准地图朝向 |
| **输出 PNG 名** | `miniinsplot_<ttl>.png` / `miniavpcmpplot.png` / `miniinsplot3d_<ttl>.png` |
| **图例** | 显式传 `legend([ht, hs], {...})` 句柄列表，避免把起点红点/多余曲线混进图例 |

??? tip "自动标签规则（不传 labels 时）"
    - 1 个解算 → `{'DR (est)'}`
    - 2 个解算 → `{'free','fix'}`
    - 更多 → `{'sol1','sol2',...}`（用 `arrayfun` 生成）

---

## 2. MATLAB 惯用法小词典（看不懂的词来这查）

按"你之前点名的顺序"讲。每条给：**它是什么 → 在本项目干嘛 → 口诀**。

### 2.1 函数签名与多模式分发

```matlab
function miniinsplot(varargin)     % 不写死形参，所有输入收进 varargin（cell 数组）
if nargin==2 && ischar(varargin{2})    % nargin = 本次调用传了几个参数
    ...                                % ischar = 判断某元素是不是字符串
elseif nargin>=3 && ischar(varargin{3})
    if iscell(varargin{1})             % iscell = 判断是不是 cell（区分 {s1,s2} 多解算 vs 单个矩阵）
        sols = varargin{1};
    else
        sols = {varargin{1}};          % 单个矩阵包成 cell，统一后续处理
    end
```

| 写法 | 含义 | 本项目作用 |
|---|---|---|
| `function f(varargin)` | 不定参数函数；多余输入全收进 `varargin`（cell） | 让一个函数同时支持「单轨迹」「对比」多种调用 |
| `nargin` | 本次调用**实际传了几个参数** | 据此分支到不同模式 |
| `iscell(x)` | x 是不是 cell 数组 | 区分 `{s1,s2}`（多解算）和单个矩阵 |
| `ischar(x)` | x 是不是字符串 | 判断某位置是不是 `ttl`（文件名后缀） |

> **口诀**：`varargin` 是"百宝袋"，`nargin` 数个数，`iscell`/`ischar` 看清类型——三者配合实现"一个函数多种签名"。

### 2.2 图形窗口：`get(0,'ScreenSize')` 与 `figure(...)`

```matlab
scrsz = get(0,'ScreenSize');   % 0 = MATLAB 的"根图形对象"（就是屏幕）；返回 [左,下,宽,高] 像素
figure('Color','w', ...
       'OuterPosition',[0.02*scrsz(3), 0.05*scrsz(4), 0.9*scrsz(3), 0.85*scrsz(4)]);
```

| 写法 | 含义 |
|---|---|
| `get(0,'ScreenSize')` | 拿显示器分辨率，`scrsz(3)`=宽、`scrsz(4)`=高（像素） |
| `figure('Color','w')` | 开一个图窗，背景白色；`'w'`=white（单字母颜色码：`r/g/b/c/m/y/k/w`） |
| `'OuterPosition',[x,y,w,h]` | 图窗在屏幕上的位置/大小（像素）；`[0.02W, 0.05H, 0.9W, 0.85H]` = 近全屏、略偏 |

> **这是纯装饰**（让交互看图时窗口大一点）。**PNG 由 Python 生成，这段对出图无影响**，可放心忽略或删。

### 2.3 子图布局：`subplot(3,2,[4,6])`

```matlab
subplot(3,2,1);   % 3 行 2 列，第 1 格
subplot(3,2,[4,6]); % 把第 4、6 格"合并"成一个大面板
```

- 编号按**行优先**：`1 2 / 3 4 / 5 6`。
- 传**向量** `[4,6]` = 把第 4 格（左下）和第 6 格（右下）合并 → 底部一整行，给大轨迹图用。

> **口诀**：`subplot(m,n,k)` 单数是单格；`subplot(m,n,[a,b])` 向量把几格拼一起。

### 2.4 图例控制（三件套）

```matlab
% ① 起点红点：画了但不进图例
plot(0, 0, 'rp', 'HandleVisibility','off');

% ② 多条曲线共用一个图例项（姿态的 Pitch/Roll/Yaw 画成一次 plot 的 3 列）
h = plot(t, att(:,1:3), ...);
for j=2:3, h(j).Annotation.LegendInformation.IconDisplayStyle = 'off'; end  % 只留第 1 条(Pitch)入图例

% ③ 显式指定图例（句柄 + 文字一一对应）
legend([ht, hs], [{'Truth'}, sollbl(1:length(sols))], 'Location','best');
```

| 写法 | 含义 |
|---|---|
| `'HandleVisibility','off'` | 该图形对象不出现在图例里（起点红点 hack） |
| `h(j).Annotation.LegendInformation.IconDisplayStyle='off'` | 图形对象技巧：把第 j 条线的图例图标关掉，让多条线共用一个图例项 |
| `legend([h1,h2,...], {'名1','名2',...})` | 显式传"句柄列表 + 文字列表"，顺序对应 |

> **为什么不用 `legend('Truth','free')` 这种按出现顺序的写法？** 因为起点红点、多条曲线会污染自动图例（你之前在 Python 版就踩过这个坑）。显式传句柄最稳。

### 2.5 时间对齐：`interp1`

```matlab
h_truth = interp1(truth(:,10), truth(:,9), s(:,10), 'linear', 'extrap');
%            ↑真值时间        ↑真值高度      ↑解算时间       ↑线性、超界外推
```

把"真值高度"按**时间**插值到"解算的时间轴"上，这样两者逐点相减才有意义（解算 50 Hz、真值 100 Hz，时间戳不完全重合）。

> 等价于 Python 的 `np.interp(s_t, truth_t, truth_h)`。

### 2.6 数组与单元格：`arrayfun` / `cellfun` / `deal`

| 写法 | 含义 | 本项目例子 |
|---|---|---|
| `arrayfun(@(k)f(k), 1:N, 'UniformOutput',false)` | 把匿名函数逐个作用到 `1:N`；`'UniformOutput',false` 表示返回 **cell**（字符串数组）而非数值矩阵 | 自动生成 `{'sol1','sol2',...}` 标签 |
| `cellfun(@f, C)` | 把函数作用到 cell 数组 C 的每个元素 | （本系列较少用） |
| `[a,b] = deal(x, y)` | 一次返回多个输出 | `enu = @(a) deal(East, North)` 同时返回东、北两向量 |

> **匿名函数 `@(k) ...`**：没有名字、一行写完的小函数，`k` 是它输入的占位符。

### 2.7 角度与坐标小工具

```matlab
de(:,3) = mod(de(:,3)+pi, 2*pi) - pi;   % yaw 误差归一到 [-pi, pi]
range(x)                                 % = max(x)-min(x)，用于轴边距
strdms = @(d) sprintf('%03d%02d%05.2f', ...);  % 度分秒(DMS) 字符串格式化，对齐 PSINS 图例
```

- **`mod(de+pi,2*pi)-pi`**：把角度差包回 `[-π, π]`。没有它，yaw 从 `179°` 跳到 `-179°` 会被算成 `358°` 的巨大误差，曲线画出垂直毛刺。
- **`range(x)`**：数据跨度，用来给坐标轴留 2% 边距（`min-0.02*range, max+0.02*range`）。
- **`strdms`**：把纬度/经度格式化成 `dddmmss.ss`（度分秒），PSINS 图例用这种格式。

### 2.8 保存图片：`saveas` / `close`（为什么注释掉）

```matlab
% saveas(gcf, sprintf('miniinsplot_%s.png', ttl));  % 把当前图窗存成 PNG
% close(gcf);                                        % 关掉图窗
```

三个 `.m` 里这两行**默认注释**。原因：**本环境的 `matlab -batch` 一开图窗就崩**（access violation），所以 PNG 实际由 **Python 版 `miniplot.py` 生成**。`.m` 里的 `saveas` 保留给"你有带界面的 MATLAB、想手动导出"时用——取消注释、在 MATLAB 里直接运行函数即可。

---

## 3. 双轨说明：`.m` 是参考、`.py` 出图

| | `.m`（MATLAB） | `.py`（Python / `miniplot.py`） |
|---|---|---|
| 角色 | **参考实现**（对齐 PSINS 画法） | **实际出图**（生成 wiki 里的 PNG） |
| 函数名 | `miniinsplot` / `miniavpcmpplot` / `miniinsplot3d` | 同名 `miniinsplot` / `miniavpcmpplot` / `miniinsplot3d` |
| 能否跑图 | `matlab -batch` 开图会崩；需带界面 MATLAB 手动跑 | 零依赖（`matplotlib`），CI/命令行直接出 PNG |
| 价值 | 和 Python 跑**同一套数学**，结果逐数字一致 → 本身是一重交叉验证 | 不绑定 MATLAB 许可证，wiki 可复现 |

> **所以**：你想读懂"图是怎么画的"→ 看 `.m`（结构清晰、对齐 PSINS）；你想改数值/重出图 → 改 `.py` 跑。两者逻辑 1:1 对应。

---

## 4. 可复现：如何自己跑出这些图

```bash
# 进资产目录
cd docs/惯性导航/assets

# Python（实际出图，零依赖）
python gen_sins.py     # 生成 P2 的 fix/free 系列图 + 3D 图
python gen_dr.py       # 生成 P3 的 DR 对比图

# MATLAB（仅参考；需带界面 MATLAB，并取消 .m 里 saveas 注释）
% 在 MATLAB 命令行直接调用，例如：
%   trj = ...; avp_free = ...; avp_fix = ...;
%   miniinsplot({avp_free, avp_fix}, trj, 'cmp_freefix');
```

??? note "新人建议的阅读顺序"
    1. 先读 P1/P2/P3 正文，知道这些图在讲什么物理量；
    2. 想改图或看懂代码时，回来看本页第 1 节（函数签名）和第 2 节（惯用法词典）；
    3. 直接读 `assets/miniinsplot.m` 顶部注释 + 本页，基本能无障碍跟下来。

---

相关：[← 拆解 PSINS 篇总览](../index.md) · [P2 纯惯导](P2_纯惯导_拆解test_SINS.md)

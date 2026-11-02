# 02b 四元数 → 方向余弦矩阵 $C_b^n$ 的完整推导（轴角 + Rodrigues 公式）

> 本页是 [02 姿态的四种表示 · §三-2](02_姿态的四种表示.md) 里那个只含 $q_0,q_1,q_2,q_3$ 的 $C_b^n(\boldsymbol q)$ 矩阵的**完整推导**。主页面为了不喧宾夺主，只摆结论矩阵，把"它从哪来"挪到这里单讲。

## 0. 我们要解的问题

已知单位四元数 $\boldsymbol q=(q_0,q_1,q_2,q_3)=(w,x,y,z)$（Hamilton 序，已单位化 $\|\boldsymbol q\|=1$），要直接写出它对应的方向余弦矩阵（旋转矩阵）$C_b^n$。

关键认知：**四元数本质是"绕单位轴 $\mathbf u$ 转 $\theta$ 角"**。所以推导路线是：

$$\text{轴角}(\mathbf u,\theta) \;\xrightarrow{\text{四元数编码}}\; \boldsymbol q \;\xrightarrow{\text{Rodrigues}}\; \text{旋转矩阵 }R$$

最终矩阵只含 $q_0,q_1,q_2,q_3$，且**与欧拉角序列无关**——这正是"四元数→DCM 是唯一桥梁"的来由。

## 1. 轴角 ↔ 四元数

设单位四元数为：


$$q = q_0 + q_1 i + q_2 j + q_3 k, \quad \|q\| = 1$$


它与旋转轴 $\mathbf{u} = (u_x, u_y, u_z)$（单位向量）和旋转角 $\theta$ 的关系为:

$$q_0 = \cos\frac{\theta}{2}, \quad 
\begin{pmatrix} q_1 \\ q_2 \\ q_3 \end{pmatrix} = \sin\frac{\theta}{2} \begin{pmatrix} u_x \\ u_y \\ u_z \end{pmatrix}$$

反过来 $\mathbf u=\dfrac{(q_1,q_2,q_3)}{\sin(\theta/2)}$，且 $\sin\frac{\theta}{2}=\sqrt{q_1^2+q_2^2+q_3^2}$（因 $\|\boldsymbol q\|=1$）。

## 2. Rodrigues 旋转公式（轴角 → 矩阵）

对于绕单位轴 $\mathbf{u}$ 旋转 $\theta$ 角度的旋转，其旋转矩阵为：

$$R = I + \sin\theta\,K + (1-\cos\theta)\,K^2$$

其中 $I$ 是 $3\times3$ 单位矩阵，$K$ 是 $\mathbf{u}$ 的叉积矩阵（反对称阵）：

$$K=\begin{bmatrix}0&-u_z&u_y\\ u_z&0&-u_x\\ -u_y&u_x&0\end{bmatrix}$$

并且有性质 $K^2 = \mathbf{u}\mathbf{u}^T - I$（因为 $\|\mathbf{u}\|=1$）。

## 3. 半角代换：把一切都换成 $q$

目标：消去 $\theta$ 和 $\mathbf u$，只留四元数分量。

- $$\sin\theta = 2\sin\frac{\theta}{2}\cos\frac{\theta}{2} = 2 q_0 \sqrt{q_1^2+q_2^2+q_3^2} \quad (\text{注意 } \sqrt{q_1^2+q_2^2+q_3^2} = \sin\frac{\theta}{2})$$
- $\mathbf u = \dfrac{(q_1,q_2,q_3)}{\sin(\theta/2)}$

**先处理 $\sin\theta\,K$**：把 $\sin\theta$ 里的 $\sin\frac{\theta}{2}$ 和 $\mathbf u$ 分母里的 $\sin\frac{\theta}{2}$ 约掉：

$$\sin\theta\,K = \big(2q_0\sin\tfrac{\theta}{2}\big)\cdot\frac{1}{\sin(\theta/2)}\begin{bmatrix}0&-q_3&q_2\\ q_3&0&-q_1\\ -q_2&q_1&0\end{bmatrix} = 2q_0\begin{bmatrix}0&-q_3&q_2\\ q_3&0&-q_1\\ -q_2&q_1&0\end{bmatrix}$$

**再处理 $(1-\cos\theta)K^2$**：由 $\cos\theta=2\cos^2\frac{\theta}{2}-1=2q_0^2-1$ 得

$$1-\cos\theta = 2\sin^2\frac{\theta}{2} = 2(q_1^2+q_2^2+q_3^2)$$

而 $K^2=\mathbf u\mathbf u^T-I=\dfrac{1}{\sin^2(\theta/2)}(q_1,q_2,q_3)^T(q_1,q_2,q_3)-I$，所以

$$(1-\cos\theta)K^2 = 2(q_1^2+q_2^2+q_3^2)\left(\frac{1}{q_1^2+q_2^2+q_3^2}\begin{pmatrix}q_1\\q_2\\q_3\end{pmatrix}\begin{pmatrix}q_1&q_2&q_3\end{pmatrix}-I\right) = 2\begin{pmatrix}q_1\\q_2\\q_3\end{pmatrix}\begin{pmatrix}q_1&q_2&q_3\end{pmatrix}-2(q_1^2+q_2^2+q_3^2)I$$

## 4. 三项合并 + 逐元素展开

把 $I$、$\sin\theta\,K$、$(1-\cos\theta)K^2$ 三项相加，第一项 $I$ 与最后一项的 $-2(q_1^2+q_2^2+q_3^2)I$ 合并成 $\big(1-2(q_1^2+q_2^2+q_3^2)\big)I$：

$$R = \big(1-2(q_1^2+q_2^2+q_3^2)\big)I + 2q_0\begin{bmatrix}0&-q_3&q_2\\ q_3&0&-q_1\\ -q_2&q_1&0\end{bmatrix} + 2\begin{pmatrix}q_1\\q_2\\q_3\end{pmatrix}\begin{pmatrix}q_1&q_2&q_3\end{pmatrix}$$

逐元素写出（第 $i$ 行第 $j$ 列）：

- 对角：$R_{11}=1-2(q_2^2+q_3^2)$，$R_{22}=1-2(q_1^2+q_3^2)$，$R_{33}=1-2(q_1^2+q_2^2)$；
- 非对角（盯住 $q_0$ 交叉项符号）：$R_{12}=2(q_1q_2-q_0q_3)$，$R_{13}=2(q_1q_3+q_0q_2)$，$R_{21}=2(q_1q_2+q_0q_3)$，$R_{23}=2(q_2q_3-q_0q_1)$，$R_{31}=2(q_1q_3-q_0q_2)$，$R_{32}=2(q_2q_3+q_0q_1)$。

## 5. 最终矩阵

$$
C_b^n=
\begin{bmatrix}
1-2(q_2^2+q_3^2) & 2(q_1q_2-q_0q_3) & 2(q_1q_3+q_0q_2) \\
2(q_1q_2+q_0q_3) & 1-2(q_1^2+q_3^2) & 2(q_2q_3-q_0q_1) \\
2(q_1q_3-q_0q_2) & 2(q_2q_3+q_0q_1) & 1-2(q_1^2+q_2^2)
\end{bmatrix}
$$

> 📌 **唯一性 & 约定**：上式是**唯一**的（从轴角即旋转本身构造，不依赖任何欧拉角序列）。约定 **Hamilton 序 $[w,x,y,z]$ + 被动 body→NED**。因 $C_b^n$ 正交，其逆（nav→body）就是转置 $C_n^b=(C_b^n)^T$。若你的库是 $[x,y,z,w]$ 序或 ENU 系，符号会整体翻转——**务必以代码实际输出为准**（见主页面 §三-2 矩阵块的 ⚠️）。

> 🔬 **数值闭环**：把主页面 §三-3 验证过的 ZYX$(30^\circ,20^\circ,10^\circ)$ 反解成**严格单位**四元数 $q\approx(0.951549,\;0.038135,\;0.189308,\;0.239298)$（$\|q\|^2=1.0$），代回上式，与 Rodrigues 矩阵、与原 DCM 三者逐元素相等（误差 $<10^{-12}$）。§三-3 表格里写的 $(0.9515,0.0381,0.1893,0.2393)$ 只是 4 位四舍五入，所以当时看着差约 $7\times10^{-5}$——不是公式有误差，是 $q$ 被截断了。

---

← 返回 [02 姿态的四种表示](02_姿态的四种表示.md)

# verify/ —— Mini-INS 回归自检

本目录是库的"体检"：确定性（固定种子/无随机）、无工具箱、一次跑完给 PASS/FAIL。

| 脚本 | 验证什么 | 当前状态 |
|---|---|---|
| `verify_trans.m` | 基础转换模块（9 组：互逆性 / 合成一致性 / 已知值） | ✅ 全 PASS |
| `verify_ins.m` | insupdate 机械编排（姿态更新 yaw=90° + 静止比力自洽） | ✅ 全 PASS |
| `verify_trj.m` | 轨迹生成正演→反演自洽（trjsimu 生成 imu → insupdate 复现 avp） | ✅ 全 PASS |
| `verify_dr.m` | 航位推算航向×里程自洽（M4 版：P4 WAT + odsimu + 体 y 里程） | ✅ M4 Python 预验证通过（无误差 DR RMS 1.6 m） |
| `compare_psins.m` | 与 PSINS 原版同参数对拍（计划，需本地 PSINS） | 规划中 |

## 怎么跑

```matlab
cd docs/惯性导航/assets/miniins/verify
verify_trans        % → VERDICT: ALL PASS
verify_ins          % → VERDICT: ALL PASS
verify_trj          % → VERDICT: ALL PASS（M2，M4 版 trjsimu 自洽 2e-8 rad）
verify_dr           % → VERDICT: ALL PASS（M4 版）

% —— M4 验收：SINS+DR 组合导航完整仿真（对拍 P4 基准）——
cd ../demos
demo_sins_dr        % 期望：SINS-only ≈345 / DR-only ≈151 / 组合 ≈45.5 m
```

## 与 PSINS 的对拍基准（来自拆解系列，供 compare_psins 对照）

| 场景 | PSINS 原版 | Mini-INS（期望） | 出处 |
|---|---|---|---|
| 纯惯导水平位置误差末点 | 935.9 m | 936.0 m | [P2](04_拆解PSINS篇/P2_纯惯导_拆解test_SINS.md) |
| SINS+DR 组合水平 RMS | 43.2 m（dkod=1%） | 45.5 m（dkod=5%，轨迹不同） | [P4](04_拆解PSINS篇/P4_SINS+DR组合_拆解test_SINS_DR.md) |
| SINS+DR：SINS-only / DR-only / 组合 | — | 345 / 151 / 45.5 m（P4 WAT，966 s） | M4 demo_sins_dr |

## 约定

- 新写模块必须先配 verify 脚本再合入（铁律 5：确定性）；
- 改算法前先跑一遍全 verify，改完再跑，保证"改了没改坏"。

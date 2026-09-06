# SMA-SE 第二十五阶段：通流换向失败门禁与坐标诊断

日期：2026-09-07。结论：已完成新的真实通流试验及根因诊断，**库存门禁未通过**，
不得将上一阶段密闭组件的成功推广为完整网络验证。

## 1. 实际执行与测试范围

执行源码提交：`a85c89b700a296d19ac4a6c0b9043c4432faf416`。
独立台架由热储库、受控质量流量源、双口流体腔、冷储库组成。两端压力均为
2.5 MPa，储库温度 380/300 K，腔体初温 340 K，容积和水域设置沿用前阶段。
热口绝热，流量源实测压头功为 0。这是刚性定压台架，不是完整 SMA-SE 回路。

原生/守恒两种腔体分别运行正向 +0.2 g/s、反向 -0.2 g/s、0.5 s 从正向切到反向
三种工况，每种使用 1/0.5/0.25 ms 局部 BE 步长；全局 ode3 同步步长，每项 1 s。
共 18 项真实 MATLAB 仿真，单一前台进程自然结束，退出码 0。
未启动生产长周期链，未加载或修改 C200/C180 OP。

每项完整记录腔体、流量源、两储库的原生变量；总计 414 条标量轨迹，网格
1001/2001/4001 时刻。实际初值、流量方向及 0.5 s 指令切换均通过核对。
没有抽稀、平滑、删除初始点或删除事件区间。

## 2. 两套边界账本

局部账本用腔体自身 A/B/H 端口：

```text
net_mdot_local = mdot_A + mdot_B
net_power_local = Phi_A + Phi_B + Q_H
```

外部账本独立读取两个储库和流量源：

```text
net_mdot_external = -mdot_hot_reservoir - mdot_cold_reservoir
net_power_external = -Phi_hot_reservoir - Phi_cold_reservoir + flow_source_power
```

逐个连接节点检查 Through 变量互抵，以及流量源自身质量、能量平衡。
18 项所有时刻，空间质量/能量节点最大残差均为记录精度内的 0。
这证明当前空间接线及符号账本一致，**不证明时间积分库存闭合**。

两套边界均按原生本地 BE 的右端点规则积分，并与 `M=rho*V`、`U=rho*V*u`
的原生端点变化比较。继续使用质量 `1e-15 kg`、能量 `1e-8 J` 的组件门禁，未放宽。

## 3. 守恒腔体的实际失败结果

| 模式 | 步长 ms | 全时段最大质量残差 kg | 全时段最大能量残差 J |
|---|---:|---:|---:|
| 正向 | 1 | 2.28624511e-10 | 1.27768003e-4 |
| 正向 | 0.5 | 1.45177560e-11 | 4.59297668e-5 |
| 正向 | 0.25 | 1.03919300e-11 | 2.35292436e-5 |
| 反向 | 1 | 6.80167457e-19 | 8.59160657e-5 |
| 反向 | 0.5 | 7.72070531e-19 | 4.29607399e-5 |
| 反向 | 0.25 | 1.14603558e-18 | 2.14810467e-5 |
| 换向 | 1 | 7.75524838e-19 | 9.65345095e-5 |
| 换向 | 0.5 | 1.37315952e-18 | 4.82701453e-5 |
| 换向 | 0.25 | 2.16236924e-18 | 2.41358099e-5 |

能量门禁九项全部失败；正向质量门禁也失败。相比原生组件的差额虽然明显减小，
仍不能改判通过。原始 `open_flow_audit_v1.json` 和新增诊断的 `open_flow_audit_v3.json`
都保留这些失败值，不将诊断差额从物理账本中扣除。

## 4. 已证实的数值关系与推断边界

定压下，对原生同一轨迹按物性表的分段线性温度导数计算：

```text
M_T = V * rho_T
U_T = V * (rho_T * u + rho * u_T)
BE_mass_in_temperature_coordinate = M_T[n] * (T[n]-T[n-1])
BE_energy_in_temperature_coordinate = U_T[n] * (T[n]-T[n-1])
```

九项守恒工况，这两式与实际端口积分的单区间最大差额分别仅
`2.76134e-20 kg`、`1.82999e-13 J`。端点库存减去这组链式差分，能够解释前述
质量与能量差额。解释不需要修改一个原始样本。

正向工况从 340 K 升至约 344.788 K，跨过密度/内能表的 343.16 K 节点。
三档步长的跨节点右端时刻为 0.646、0.646、0.64575 s；质量跳差集中在对应区间。
反向及换向工况未跨越温度表节点，其质量残差近浮点范围，但 `rho*u` 非线性乘积的
链式 BE 差分仍不等于严格端点差，能量差额随步长缩小而下降。

这里证实的是**观测轨迹符合温度坐标的 BE 链式差分**，不是直接读取到了编译器选择
的状态变量。MathWorks 说明动态变量可能产生独立或依赖状态，求解器会消元后再映射
状态向量。因此“声明 der(M)/der(U) 就保证所有网络里按 M/U 直接离散积分”并不成立；
具体状态选择仍须另行观测，不能由声明形式直接断言。
[官方说明：Equation Construction](https://www.mathworks.com/help/simscape/ug/how-simscape-simulation-works.html)。

## 5. Fig13 逐图解释与审核

文件：
`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/chamber_open_flow_20260907_v2/Fig13_open_flow_failure_localization_v2.png`

1. 左图：1 ms 换向试验的 A/B 实测有符号流量，显示 0.5 s 的真实换向；两个端口
   流量绝对值不必完全相等，因为腔体温度变化引起库存变化。
2. 中图：1 ms 正向试验的质量积分残差。跳变在跨表节点区间，不在流量换向时刻。
3. 右图：三种工况的全时段最大能量残差随步长变化。虚线为未改变的门禁，所有
   曲线均在其上，不因为下降趋势而判为通过。

已查看 2860x924 PNG；去除了初版对数横轴拥挤的小刻度标签，无裁切重叠。
废弃初版 PNG 的哈希和替代图哈希已保留，删除 171369 bytes。
这不是最终论文性能图，也不表示 SCI 审稿通过。

## 6. 接线失败与测试覆盖

首次执行 `9bfb264` 在接线前检查阶段退出，0 个仿真工况。M 口实际存在，错误来自
`strcmp({port.Name},'M')` 的单元格 string 比较。单独 MATLAB 诊断确认原表达式
返回 `[0 0 0]`，逐项 char 比较返回 `[0 0 1]`。修复后，先用公共命名连接映射 A/B
液体端口，再由剩余唯一句柄确定控制输入，不猜端口编号。

离线加入坐标诊断时，一次调用被放入读取器导致 NameError；移至审核函数，增加
确定性 HDF5 读取测试。未为此重复 MATLAB 仿真。最终 112 项 Python 测试通过，
本阶段新增 9 项，包括符号、事件区间保留、内部异常不被末点抵消、解析乘积链式差、
跨表节点质量差和原生数据读取。两类软件失败及原始科学失败均保留。

## 7. 结果包、代码及复核

仓库：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote`。
数据：`outputs_storage_audit/chamber_open_flow_20260907_v2`。
发布包：`outputs_storage_audit/open_flow_diagnostic_release_20260907`。

沿用 Stage17 完整源码 ZIP 加本阶段直接从 Stage17 基提交生成的增量 patch，
不叠加中间 patch，不复制生产大 MAT。清单逐项记录原位文件长度与哈希，递归核对
C200/C180 冻结依赖。新原生数据仍有明确诊断用途，保留 18 项紧凑 MAT。

```powershell
$repo = 'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'
& "$repo/verification/Audit_HeatDriveECC_OpenFlowDiagnosticPackage.ps1"
python -m unittest discover -s "$repo/verification" -p 'test_*.py' -v
python "$repo/verification/Audit_HeatDriveECC_ChamberOpenFlowResult.py" --repo "$repo" --output "$repo/outputs_storage_audit/chamber_open_flow_20260907_v2/recomputed_independent.json"
```

重算目标必须是不存在的新文件。包可报告 `package_integrity_pass=true`，但必须同时
显示 `scientific_inventory_gate_pass=false`；重算科学审核必须仍显示
`tested_open_flow_inventory_closure_verified=false`。这一区分是结果合同，不是审核漏洞。

MATLAB 重跑入口为 `verification/Audit_HeatDriveECC_ChamberOpenFlow.m`，参数为
新输出目录及 C181 的 `segment_physical.mat` 路径，形式与第二十四阶段重跑命令相同。
它只读取 options，不读取 OP；新执行身份需另建合同，不能覆盖冻结试验。

## 8. 接下来如何推进完整目标

1. 先增加有限出口阻力的独立台架，将刚性定压约束与可变腔压区分开，实际测量
   非零流量源功。这更接近有阀/管阻的主网络，但必须保留当前刚性边界失败，不能
   用另一个更容易通过的算例覆盖它。阻力是诊断变量，不是为拟合 Table 4 随意加阻。
2. 获取实际状态/消元证据，检验连续守恒、离散坐标、表节点事件三者的关系，再决定
   组件状态形式和局部积分协议，不能只调初始化优先级或偷偷放宽库存门禁。
3. 候选组件通过相关边界后，才设计完整状态兼容与无重置的诊断接入。C200 主基准、
   C180 受限诊断合同及所有失败检查点保持原状态，未解锁生产续算。
4. 完整系统内部周期稳态、全设备守恒、固定 Tc outer solve、正交敏感性、成对
   zero-load/zero-lift Table 4、系统 COP/work trade-off 和外部 validation 仍未完成。

目标保持未完成，不把本轮失败诊断封装为“完整复现成功”。

# SMA-SE 第二十四阶段：守恒库存组件修正与配对试验

日期：2026-09-07。状态：真实密闭组件修正通过；完整耦合系统与 Table 4 尚未完成。

## 1. 本轮核心进展

上一阶段证明了原生泵腔按局部 BE 步长收敛，但解所趋近的微分方程不保证端点
`rho*V`、`rho*V*u` 严格闭合。本轮新增一个实际可编译、可运行的 Simscape 守恒库存
组件，直接以总质量和总内能承接端口输运，并完成与原生腔体的配对试验。

**不是修改原始日志或另选公式把报告残差改为零，而是改变了独立组件的状态方程，
重新运行真实 Simscape，得到新的原生轨迹。生产主线没有替换该组件。**

通过批次执行提交：`3484fa1dcc78753b6ad63d7ccad557203d286dfa`。
24 项试验在一个前台 MATLAB 进程中自然结束，退出码 0，未运行监控循环或定时器。
`checkcode` 无告警，每项实际执行编译更新、仿真和原生初值检查。

## 2. 新组件与保留的边界

源码：
`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/verification/simscape_inventory/+ecc_inventory/conservative_chamber.ssc`

```text
M = V * rho(T,p)
U = M * u(T,p)
dM/dt = mdot_A + mdot_B
dU/dt = Phi_A + Phi_B + Q_H
```

仍使用现有水域的同一密度、内能表；保留两个 Thermal Liquid 端口和原生
`foundation.thermal_liquid.port_convection` 对流实现，保持等压腔体、固定容积及热口。
不改水物性表、不拟合附加热源、不补偿端点质量，不从失败批次或生产 OP 初始化。

原生组件以 p/T 微分系数累计质量能量，新组件以表定义的库存 M/U 积分，
因而两者的压力与温度响应不必相同。新组件只证明这一守恒建模选择在本试验条件下
可实现，不证明其所有物理假设优于原生组件，也不等同于 Qian 模型。

当前仅测试真实水域的矩形温压有效区间；新组件位于验证命名空间，不进入生产构建。
尚未测试通流、流向切换、不同流体、跨物性节点的强扰动、接入全系统后的刚性或 OP
兼容性。新库不得当作经过完整验证的通用元件发布。

## 3. 配对合同与独立核对

同一原生水域，容积 `1.6084954386379741e-6 m3`，端口面积
`8.04247719318987e-6 m2`，初压 2.5 MPa，初温 300/380 K，
恒定热输入 +5/-5 W，每项 1 s，本地 BE 和全局 ode3 同步使用 1/0.5/0.25 ms。
共原生 12 项、守恒 12 项。水域允许压力为 0.45-5 MPa，未外扩物性域。

检查完整原生网格 1001/2001/4001 时刻，两个端口各自质量流和能量流为零，实际
热口方向正确。原生组记录 9 个坐标，守恒组另记录 `stored_mass/stored_energy`，
并将它们与原生 `rho*V/rho*V*u` 逐点核对。

独立端点解不采用 Simscape 轨迹作目标或初猜。由初始表值直接建立：

```text
rho(T_end,p_end) = rho(T_initial,p_initial)
u(T_end,p_end) = u_initial + Q_H * 1s / M_initial
```

再通过独立非线性代数求解反演终点温压。没有改变微分方程残差容限来迁就结果。
预设端点库存全轨迹绝对门禁为质量 `1e-15 kg`、能量 `1e-8 J`；独立温压解
对照门禁为 `1e-8 K / 0.01 Pa`。这些仅是本密闭组件算例的精度要求。

## 4. 实际结果

下表列 1 ms 档，其余两档全部保存在审核 JSON 中并共同参与门禁。

| 初温 / 热输入 | 原生端点质量变化 micro-g | 原生端点能量超额 mJ | 守恒端点质量变化 kg | 守恒端点能量超额 J |
|---|---:|---:|---:|---:|
| 300 K / +5 W | +20.45124618 | +2.17832731 | 0 | -4.54747e-12 |
| 300 K / -5 W | -11.59326393 | -0.71899957 | 0 | +4.51905e-12 |
| 380 K / +5 W | +14.36732625 | +1.24995430 | 0 | -4.43379e-12 |
| 380 K / -5 W | -8.66002211 | -0.12752522 | 0 | +4.66116e-12 |

全部 12 项守恒工况、全部时刻：质量残差最大为记录精度内的 0；能量残差最大
`1.0925305105e-10 J`。总能量变量与 `rho*V*u` 最大别名差 `3.4106e-13 J`。
独立端点解的最大温差 `1.92131e-11 K`、压差 `3.22997e-5 Pa`。
原生组 12 项在同一库存门禁下均未通过质量及能量闭合，不能用其“仿真退出 0”替代门禁。

温压变化不是完全不受影响。例如 300 K/+5 W/1 ms：原生终点约
`300.75523847 K / 2.94454120 MPa`，守恒终点约
`300.75471858 K / 2.91685102 MPa`。约 27.69 kPa 压差可能影响压差驱动回路，
所以绝不能把组件替换称为对完整网络性能无影响的纯后处理修正。

## 5. Fig12 逐图解释

`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/conservative_chamber_20260907_v4/Fig12_conservative_inventory_comparison.png`

1. 左图为无流体进出时端点质量变化，区分加热/冷却、两种初温与两种模型。
   蓝柱不是实际补液，表示原生密度端点库存偏差；绿色短标记位于零线上。
2. 右图为端点内能变化减去实测净热输入。正值为库存增加超过边界输入，负值相反。
   保留符号，不把热量和质量混在双纵轴中。绿色结果在该尺度下接近零，精确值见表。

已查看 2400x1056 PNG，无遮挡、重叠或裁切，图注明确限于密闭试验，不宣称
通流或全网络验证。它是诊断图，不是最终 Qian 对标主文图或期刊审稿通过证明。

## 6. 失败链与修复，不隐藏反例

1. 最初静态检查在 `0c6d7e1` 的工况 trace 名称数组追加处发现 AGROW。
   仿真未开始，修为分支完整字面量，保留退出 1 日志。
2. `7bb4d81` 库生成失败。单独编译诊断提取到根因：旧式端口位置注释不能使用相邻侧。
   将 H 口位置注释改为左侧，并保存完整异常链；未改守恒式。
3. `3b13b26` 真正运行 24 项并退出 0，但原生审核拒绝：新库块默认 `p_I_specify`
   和 `T_I_specify` 均为 off，守恒组未采用请求初值，而是从 300 K、1 MPa 开始。
   不得把它作为配对成功。检查生成 SLX XML 定位后，显式启用覆盖开关，增加
   MATLAB 原生初值立即检查，再产生独立 v4 批次。
4. 离线单位转换还发现原共享字典不支持总能量 J。增加精确 J-to-J 项，仍拒绝
   把 W 或 J/kg 当成 J；没有重复 MATLAB 仿真解决这个审核器问题。

旧失配批次保留拒绝标记、24 项合同、原始 SHA-256/长度、首末值、各坐标范围及
两个正负热输入原始反例。其余 22 个失配 MAT 经逐项哈希和绝对路径检查后删除，
释放 `4,813,323 bytes`。v1/v2 编译前失败及完整原因也继续保留。新有效 v4 不清理原始数据。

## 7. 完整代码、结果包与复核命令

仓库：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote`。
有效数据：`outputs_storage_audit/conservative_chamber_20260907_v4`。
发布入口：`outputs_storage_audit/conservative_chamber_release_20260907`。

本包以 Stage17 完整源码 ZIP 加本阶段直接从 Stage17 基提交生成的 patch 组成
完整源码，不叠加中间阶段 patch，不复制 GiB 级生产 MAT。原位数据清单记录每个
必要结果的长度、SHA-256；发布合同记录最终源代码提交。冻结 C200/C180 包递归复核。

```powershell
$repo = 'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'
# 只读核验本阶段与依赖包。
& "$repo/verification/Audit_HeatDriveECC_ConservativeChamberPackage.ps1"
# 全套 Python 测试。
python -m unittest discover -s "$repo/verification" -p 'test_*.py' -v
# 从保留的原生轨迹重新计算，输出必须是不存在的新文件。
python "$repo/verification/Audit_HeatDriveECC_ConservativeChamberResult.py" --repo "$repo" --output "$repo/outputs_storage_audit/conservative_chamber_20260907_v4/recomputed_independent.json"
```

应看到 `actual_simscape_cases=24`、`sealed_component_inventory_closure_verified=true`。
`open_port_transport_verified`、`switched_network_verified`、`whole_model_first_law_verified`、
`production_recovery_allowed`、`table4_reproduction_claim` 必须仍为 false。
全测试覆盖解析端点、热量正负号、内部中间时刻库存异常、单位混用、初值失配拒绝，
以及原有全部模型账本测试。

封装前实际执行全部 103 项 Python 测试，通过；本阶段新增 8 项。

真实组件重跑入口为 `verification/Audit_HeatDriveECC_ConservativeChamber.m`，在干净、
已提交工作树中运行，使用全新输出目录：

```matlab
cd('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote');
addpath('verification');
Audit_HeatDriveECC_ConservativeChamber( ...
 'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/conservative_chamber_independent_rerun', ...
 'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181/segment_physical.mat');
```

它会编译本验证命名空间，连续跑 24 项；不保存生产 OP。不同提交的独立重跑须
另建身份合同，不得替换本冻结批次。

## 8. 下一步与主目标边界

下一步首先检验开放端口、正反向通流及切换下的质量/能量输运，再决定是否将候选
守恒形式接入诊断网络。只有完成实际状态映射、无重置证明和严格恢复审核后，才可能
进入完整周期比较。当前不删除四罐，不以 Qian 2015 简化假设为任意降库存的许可。
文献 Fig.6、Eq.28-30 的页码与原件位置见第二十三阶段第 5 节。

以下主目标仍未完成：完整内部周期稳态、全设备一阶守恒、有效固定 Tc outer solve、
UA/热容/库存等正交敏感性、共同参数下的成对 Table 4、热驱动系统 COP 与工作图，
以及外部 validation。保留 C200 主基准与 C180 受限诊断链；新密闭组件试验不得被
用作任何主线恢复源，也不得宣布已经完成 Qian 复现。

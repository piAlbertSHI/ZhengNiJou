# SMA-SE 正逆耦合：第二十一阶段罐热容与静压输运核对报告

日期：2026-09-07。承接第二十阶段，目标仍是完整系统边界、内部周期稳态、机制保护的 outer solve、敏感性、成对 Table 4 和最终设备性能审核。本阶段没有新增生产循环，没有替换任何恢复点。

## 1. 本阶段解决的问题

此前四罐在 1 ms 局部 Backward Euler 下仍存在能量残差，不能仅用梯形积分误差解释。本阶段识别出旧诊断账本的两个遗漏：

1. 罐的有效温度积累系数包含额外热容，等效体积为截面积乘以 **1 mm**。四个实际罐的面积均为 `0.001 m²`，对应每罐 **1 mL**。这个预测经过六个独立组件试验验证，不是将 C181 残差拟合成自由参数。
2. 单入口罐还需区分端口能流与液位参考面的内部能流，差额为 `-mdot_A * g * (level - inlet_height_A)`。使用实际液位和流量后，C181 四罐全部 40000 个保留区间的离散能量差都落入按浮点温度相减推导的数值误差范围。

**准确结论是“四个罐的离散能量方程核对通过”。** 不能因此把完整系统连续能量闭合、时间收敛、原生质量库存守恒、内部周期稳态或 Table 4 复现标为通过。旧结果完整保留，后处理没有改动任何温度、质量、相分数或 PI 状态。

## 2. 实际代码与实验

实际 MATLAB 试验提交：`322a6b7affa7bee46c91d046f2bf5b1ebefcca0a`。

| 文件 | 实际作用 |
| --- | --- |
| `verification/Export_HeatDriveECC_TankGeometry.m` | 从 C181 保存的 options 构建模型，读取四罐掩膜表达式及解析后的面积、压力、液位和温度初值；不运行主模型、不加载 OP |
| `verification/Audit_HeatDriveECC_IsolatedTankCapacity.m` | 复制真实 Tank、真实两种流体设置到独立小模型，执行六个 0.1 s 试验；无主线 OP、无输出 OP |
| `verification/Audit_HeatDriveECC_TankEnergyBasis.py` | 独立读取 MAT、物性表和几何，对组件试验与 C181 原生数据计算两项差额；保留梯形和 BE 两类定义 |
| `verification/test_tank_energy_basis.py` | 测试面积缩放、冷热符号、端点取值、零温变、静压输运方向和非法输入拒绝 |
| `verification/Audit_HeatDriveECC_TankBasisPackage.ps1` | 复核前阶段冻结包、当前结果哈希和声明边界，生成完整基包到当前提交的代码增量；不复制生产 raw |

几何导出第一次只记录表达式，第二次明确解析实际值，两个 JSON 都保留。`volume=5 m³` 和 `mass=5000 kg` 是未启用的变量默认目标，不能作为当前流体库存；本阶段使用原生记录的质量与体积。实际初始化选中液位和内部温度目标。

真实试验只启动一次前台 MATLAB，沿同一 session 等待自然结束，最终 **exit_code=0、CASES=6**。没有定时器、监控进程、重复启动、取消健康 MATLAB 或改变严格恢复设置。

## 3. 独立组件干预

两种流体分别来自真实 SMA 水域和 SE 丙二醇水溶液域。每种流体的面积取 `0.0005 / 0.001 / 0.002 m²`，初始液体体积均为 `0.0001 m³`，相应改变初始液位；初始温度分别为 380 K 和 280 K，压力 1 MPa。全局 ode3 与局部 BE 步长均为 1 ms。每次保留 101 点、100 区间，无抽样或删除端点。

入口仅接设置块和求解器，实测质量流量和端点质量变化为零。命令与热源方向分开记录：因热源 A/B 朝向，水侧命令 +10 W 对应罐 `Q_H=-10 W`，SE 侧命令 -10 W 对应 `Q_H=+10 W`；审核始终使用原生 Q_H，不将命令符号冒充实际输入。

| 流体 | 面积 m² | 预先固定的额外体积 mL | 旧 BE 周期残差 J | 加入额外热容后的最大单步残差 J |
| --- | ---: | ---: | ---: | ---: |
| 水，380 K 冷却 | 0.0005 | 0.5 | -0.00497512920 | 1.14274e-11 |
| 水，380 K 冷却 | 0.0010 | 1.0 | -0.00990099956 | 1.14778e-11 |
| 水，380 K 冷却 | 0.0020 | 2.0 | -0.01960786153 | 1.15919e-11 |
| SE 流体，280 K 加热 | 0.0005 | 0.5 | +0.00497512202 | 1.06970e-11 |
| SE 流体，280 K 加热 | 0.0010 | 1.0 | +0.00990098542 | 1.07247e-11 |
| SE 流体，280 K 加热 | 0.0020 | 2.0 | +0.01960783404 | 1.08077e-11 |

这证明实际安装版本中额外温度积累项的面积缩放行为。没有改变主线罐面积、液位或温度。这六个组件冷初值属于独立验证协议，不是把主线冷启动冒充检查点续算。

## 4. 完整 C181 的修正定义

针对当前恒压、恒截面积、单入口、入口被液面淹没的罐，核对式为：

```text
Vd = tank_area * 0.001 m
Phi_internal = Phi_A + Q_H - mdot_A * g * (level - inlet_height_A)
Phi_internal = (M + rho * Vd) * cp * dT/dt + h * dM/dt
```

BE 使用每区间右端点的物性、质量流量与能流，乘以原生时间增量；梯形定义另行保留。没有把上述 Vd 直接加到质量流率或端点液体质量里：这是当前实现中已识别的额外热容系数，尚不能冒充额外守恒的流体库存。

官方 [Tank (TL) 文档](https://www.mathworks.com/help/hydro/ref/tanktl.html)给出恒压、质量平衡和液位静压背景，但不能仅据其公开连续公式认定完整离散实现。另核对了本机公开相邻组件源码：

`C:/Program Files/MATLAB/R2025b/toolbox/physmod/fluids/library/m/+fluids/+thermal_liquid/+tanks_accumulators/tank_G_TL.ssc`

- 第 111-120 行包含 1 mm 高度和面积构成的附加体积。
- 第 535-536 行包含液位参考面的静压输运项。
- 第 903-911、942-948 行给出额外体积进入热积累、质量方程仍使用液体质量的结构。
- 源文件 SHA-256：`540A050D0BA45291BA4BF707E17D1580B87212DECA0D8B2CFFD4D449AEE4F883`。

这是 **G-TL 相邻实现的公开证据**，不是当前受保护 `tank.sscp` 的解码。额外热容已做独立几何干预；静压项本阶段通过相邻源码和真实 C181 全区间对应核对，**尚未单独做重力/入口高度干预试验**，结果 JSON 明确记录该边界。

## 5. 四罐结果与剩余问题

| 罐 | 原 BE 残差 J | 仅补热容后的残差 J | 再计静压输运后的整周期残差 J | 最大单区间残差 J |
| --- | ---: | ---: | ---: | ---: |
| SE 冷罐 | -1.0462939e-4 | -1.2847261e-5 | -1.92098e-10 | 6.30868e-11 |
| SE 热罐 | +2.3856201e-4 | +1.3650792e-5 | -1.28897e-9 | 1.40100e-10 |
| SHEX 水罐 | -0.210890067 | +2.0157882e-4 | -1.18218e-9 | 9.38500e-11 |
| SMA 热水罐 | +0.103371989 | -1.0578311e-4 | +8.15351e-12 | 8.37617e-11 |

逐区间绝对残差和分别约 `6.70686e-8 / 1.07524e-7 / 7.51599e-8 / 4.04690e-8 J`，不是仅用整周期正负抵消判断通过。数值比较限由 `16*eps*max(T)*max[(M+rho*Vd)*cp]` 给出，只解释绝对温度差分的浮点舍入规模，不是新设的物理守恒阈值。

旧 `native_ledger.json`、上一阶段 Fig09 和两个版本的定位 JSON 均保留作为历史定义证据。Fig09 下排非零差异现在有了本阶段解释，不再据此称四罐仍有同样规模的未解释能量损失。

仍未解决的约束：

1. 完整控制体账本尚需把 119 个存储元件的 BE 方程、静压内部输运、端点储能和外部边界分别汇总，防止把内部项重复计入设备输入。
2. 总端点流体质量在 C181 仍变化约 **1.18145 mg**；SHEX/SMA 水罐仍有相反的约 0.16 g 质量搬运。方程核对通过没有改变这些原生轨迹。
3. 完整内部同相位稳态、多周期质量库存、局部物理求解器收敛仍未通过。之前全局步长恢复失败证据继续保留。
4. 固定 Tc outer solve、正交敏感性、成对 Table 4、完整设备 COP 和独立物理 validation 尚未完成，不开放生产恢复资格。

## 6. 文献与下一步

本阶段修正的是 Simscape 实现核对，不是 Qian 参数重新拟合。2019 Energy 主定量文献仍位于：

`C:/Users/86182/Desktop/冷凝文献/弹热制冷文献/A heat driven elastocaloric cooling system..pdf`

已建立的页码索引为 PDF 3-4 页 Fig.1 拓扑、5 页 Eqs.(1)-(10)、16-17 页 Table 4。跨篇连接管、周期稳态和库存假设的定位见 [Qian 本地文献索引](C:/Users/86182/Desktop/正逆耦合/项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md)。本阶段没有重新逐页审读这些 PDF，不把既有索引说成新文献验证。

下一步先升级完整离散与端点双账本，再对照文献连接容积假设及设计真正的局部求解器收敛验证。不能仅因本阶段四罐方程一致，就跳过全系统库存门禁开始 Table 4 搜索。

## 7. 可运行的复核与交付

所有命令在核心目录运行：

```powershell
Set-Location 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote'
python -m unittest discover -s verification -p 'test_*.py' -v
pwsh -File verification/Audit_HeatDriveECC_TankBasisPackage.ps1
$new = 'outputs_storage_audit/owner_tank_recheck_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json'
python verification/Audit_HeatDriveECC_TankEnergyBasis.py --repo . --output $new
```

前两条分别检查 77 项测试和只读交付包；最后一条独立重算，不运行 MATLAB、不覆盖旧结果。

要有意重新执行六个组件试验，可在 MATLAB 的核心目录中运行以下独立验证入口。必须指定新的输出目录，它不生成生产 OP：

```matlab
addpath(pwd, fullfile(pwd, 'verification'));
out = fullfile(pwd, 'outputs_storage_audit', ['owner_isolated_tank_' datestr(now, 'yyyymmdd_HHMMSS')]);
physical = fullfile(pwd, 'outputs', 'qian_native_inventory_pilot_from_c180_20260906', 'cycle_181', 'segment_physical.mat');
Audit_HeatDriveECC_IsolatedTankCapacity(out, physical);
```

原始试验位于 `outputs_storage_audit/tank_energy_basis_20260907/isolated_trial`。当前完整核对为 `tank_energy_basis_v3.json`（schema v2，补齐源物理文件和相关源码哈希）；v1、v2 文件都保留，不覆盖历史。

发布目录为 `outputs_storage_audit/tank_basis_release_20260907`，含 `release.json`、逐文件 SHA-256 清单、测试日志、存储快照和源代码增量。完整源码仍使用第十七阶段完整 ZIP 加本次**直接从该基包生成的 patch**，无需叠加中间各阶段 patch；当前 Git 工作树本身就是完整最新源码。

本阶段不复制生产 MAT，也没有删除恢复/失败证据。六个组件 trace 加几何、日志和诊断 JSON 仅约 0.4 MB；全工作区精确字节数在发布时重新测量并保存，不把“本阶段删除 0 字节”冒充新释放空间。C200/C180 的冻结哈希通过前阶段依赖包一并复核。

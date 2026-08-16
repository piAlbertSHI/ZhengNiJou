# Qian 多文献锚定与完整 SMA-SE 三循环耦合修改报告

## 1. 结论边界

本轮已在唯一生产模型 `gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx`
上完成真实 1-cycle 和 3-cycle 连续 Simulink/Simscape 回归。3-cycle 的完整机制
门禁通过，证明四阶段流路、21+21 节点本构、SMA-SE 力/位移兼容、双流体域、
换热探针和能量链能够在同一时间线上连续推进。

本轮没有达到周期稳态，也没有宣称复现 Qian 2019 Table 4 的 26.2 K 或
0.64 W/g。权威结论为 `coupled_mechanism_pass=1`、`ALL_REQUIRED_PASS=0`。

## 2. 文献合同

本轮共同使用以下 Qian 系列文献，而不是只从一篇论文拼接参数：

1. `A heat driven elastocaloric cooling system.pdf`：单效系统四阶段拓扑、
   Eqs. (6)-(10)、Table 2 材料参数、Table 4 成品几何和性能目标。
2. `Thermodynamic cycle analysis of heat driven elastocaloric.pdf`：循环热力学、
   SMA-SE 等力/等位移兼容和系统参数关系。
3. `Numerical study of a double-effect elastocaloric cooling system powered by.pdf`：
   一维固液能量方程、固定 1 ms ODE3 和每子步代数兼容求解的交叉核对；本模型
   仍为单效系统，不引入双效拓扑。
4. `Numerical modeling of an active elastocaloric regenerator refrigerator with phas.pdf`：
   MAS 相变动力学形式和有限速率边界；其材料集和未报告激活体积不直接覆盖
   Qian 2019 参数。
5. `Study on high efficient heat recovery cycle for solid-state cooling.pdf`：
   换热恢复循环和状态传递边界的辅助核对。

Table 4 的 32 根直径 1 mm SMA 线、两块 0.5 x 17 mm SE 板和质量比 3.2
作为成品几何合同。Table 2 的 8 根直径 1.5 mm SMA 和 0.2 x 10 x 200 mm
SE 只用于前段算例，不与 Table 4 性能目标混用。

## 3. 代码修改

1. 本构相分数推进改为固定 1 ms Bogacki-Shampine ODE3。三个子阶段均重新
   求解 SMA-SE 兼容应力，不在阶段端点强制相分数或温度。
2. 21 节点轴向接口强制使用显式 Qian Table 4 SMA 线束体积，切断旧圆板
   `pi*R^2*t` 体积映射。
3. SE buffer 使用 Qian 2017 Table 1 的 0.1 kg 端点库存除以声明的 glycol
   密度，不再把轴向固体体积错误乘 100。
4. SE Stage 2/4 控制器改为同一物理压力源上的路线独立 PI：
   Stage 2 `Kp=-60`、`Ki=-100`，Stage 4 `Kp=-120`、`Ki=-160`，单位分别为
   MPa/(kg/s) 和 MPa/(kg/s/s)。两个积分器仅在对应路线活动时更新并保留记忆。
5. 新增稳定段瞬时流量门禁。Stage 2/4 从阶段开始 0.3 s 后要求无反向、
   最大相对误差不超过 15%、RMS 相对误差不超过 5%。阶段平均值不再能掩盖
   持续振荡。
6. 新增 Stage 3 HHEX 高温前沿门禁：超过 HHEX 初温 10 K 的连接管高温只能
   出现在 Stage 3，且不得高于同一时刻 SMA 节点最高温度加 2 K。
7. Operating Point 验证允许真实且哈希链已核对的分段续算；代理 MATLAB 结果
   和未验证检查点仍被拒绝。

生产 SLX 本轮未改写，SHA-256 为
`F1D07FDE12F442AFB2F735D5A9A833269CF433437896E2096F23AE984575EA5E`。

## 4. 一循环调参与验收

共享 PI 的原始 Stage 2 流量存在持续振荡和反向，阶段平均值曾错误通过。
三组共享增益诊断结果仅用于确定稳定边界，最终均不保留为权威结果。

最终路线独立 PI 的 1-cycle 结果：

| 阶段 | 稳定段流量范围 | 最大相对误差 | RMS 相对误差 | 反向样本 |
|---|---:|---:|---:|---:|
| Stage 2 | 3.170-3.538 g/s | 10.55% | 4.97% | 0 |
| Stage 4 | 2.944-3.177 g/s | 8.01% | 4.37% | 0 |

1-cycle 冷启动尚未完成 SE 全相变，因此只作为接口和流量回归，不作为完整机制
或性能验收。

## 5. 三循环结果

权威结果目录：

`gx101r1_R69_remote/outputs/qian_route_pi_3cycle_20260816/qian2019_table2_table4_simscape_3cycle_20260816_214010`

原始 MAT SHA-256：
`B54FB3F07E7D5F1BF831D9A36A8C1E97C62529BEEDF98E5706D6475A0188CA15`

重新验收后的报告 SHA-256：
`BF72913CF8CE810667C78D35973B51F073C6A6F405CFF2FAF54B0DD5A93288A4`。

逐循环主要结果：

| cycle | CHEX 温降 | HHEX 温升 | SE 相变摆幅 | SMA/SE 最大应力 | SMA/SE 能量残差 |
|---:|---:|---:|---:|---:|---:|
| 1 | 0.3920 K | 0.02827 K | 0.986187 | 317.63/469.59 MPa | 0.0258%/0.0451% |
| 2 | 0.4379 K | 0.00045 K | 0.990824 | 312.00/461.26 MPa | 0.0113%/0.0191% |
| 3 | 0.4419 K | 0.00002 K | 0.994317 | 310.31/458.76 MPa | 0.0182%/0.0118% |

第 3 循环稳定段流量：Stage 2 为 3.115-3.341 g/s、RMS 2.10%；Stage 4
为 3.101-3.248 g/s、RMS 1.50%，均无反向。三个循环全部机制检查通过。

3-cycle 窗口的 Eq. (9) 瞬态温跨为 1.50724 K，Eq. (10) 瞬态 SCP 为
0.382442 W/g。周期端点漂移为 0.841475 K，完整同相位温度漂移为
11.8539 K，相分数漂移为 0.399190，故这些性能值不能与 Table 4 作最终比较。

## 6. HHEX 386 K 脉冲审核

连接管峰值每次出现在 Stage 3 开始后约 0.112 s。第 3 循环峰值时：

- SMA 平均温度 392.599 K；
- HHEX-SMA 连接管出口 386.161 K；
- HHEX 主热容 303.213 K；
- 连接管入口约 304.190 K。

高温峰值低于 SMA 温度，且只在 Stage 3 出现，是高温 SMA 向 HHEX 排热形成的
有限体积热前沿，不是 Stage 1/2 到 HHEX 的短路，也不是 HHEX 主热容被强制赋温。
新增门禁已用原始 3-cycle MAT 复验通过。

## 7. 复现入口

在 MATLAB 中运行：

```matlab
restoredefaultpath;
root = 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote';
addpath(root);
cd(root);
o = struct();
o.cycle_count = 3;
o.outputs_dir = fullfile(root, 'outputs', 'manual_coupled_3cycle');
o.validation = struct('error_on_mechanism_failure', false);
audit = Validate_HeatDriveECC_EighthRound_Physics(o);
disp(audit.checks);
disp(audit.all_required_pass);
```

预期是 `audit.passed=1`、`audit.all_required_pass=0`。后者只有在周期稳态和
Table 4 定量工况均完成后才允许为 1。

## 8. 尚未完成

1. 使用真实 Simscape Operating Point 连续推进长循环，直到最后十循环完整状态
   满足温度漂移不超过 0.05 K、相分数漂移不超过 1e-4。
2. 若长循环再次出现 SE 相变摆幅衰减，必须按节点检查应力-温度-相分数过驱量，
   不得按 26.2 K 反标动力学或强制端点状态。
3. 稳态无负载工况通过后，再独立施加真实 CHEX 冷负载并搜索零温跨工况。
4. 补齐 SHEX 输入、HHEX 排热、CHEX 冷量、泵功、热漏和内部机械功抵消的闭式
   系统能量平衡，以及时间步、节点数和未报告闭合参数敏感性。

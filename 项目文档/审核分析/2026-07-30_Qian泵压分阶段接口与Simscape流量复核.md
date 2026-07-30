# Qian 泵压分阶段接口与 Simscape 流量复核

## 本次修改

- 在同一个耦合模型 `heatdrive_ecc_coupled_se21.slx` 中，为右侧 SE 的 `PressurePI_BiasSum` 接入 `SE_pressure_bias_command`。
- Stage 2 和 Stage 4 使用独立偏置，非工作阶段为零；SE 内部换热器和阀门拓扑没有重建。
- 保留左侧 SMA 的既有 `SMAPressurePI_BiasSum` 接口，并把四个阶段的 SMA/SE 压力命令统一写入同一连续 Simulink 时序。
- 将旧模板公共 PI 下限 `-0.02 MPa` 显式提升为 `-0.12 MPa`，否则 SMA 文献流量目标在压力饱和前就无法达到。

## 文献目标

- Qian 2019 Table 4：SMA 侧水流量 `50.8 g/s`，SE 侧流量 `3.2 g/s`。
- 四阶段持续时间：`3.5/1.5/3.5/1.5 s`。
- 本次命令偏置是液压工作范围内的工程闭合量，不是温度、相变分数或热量的赋值。

## 真实 Simscape 试验

### 原分阶段接口，SMA 压力上限仍为 -0.02 MPa

输出目录：
`gx101r1_R69_remote/outputs/heatdrive_ecc_qian2019_3cycle/qian2019_table2_table4_simscape_1cycle_20260730_104818`

| 阶段 | SMA 流量 | SE Stage 2 流量 | SE Stage 4 流量 |
|---|---:|---:|---:|
| 1 | 22.87 g/s | 约 0 | 约 0 |
| 2 | 约 0 | 1.62 g/s | 约 0 |
| 3 | 22.48 g/s | 约 0 | 约 0 |
| 4 | 约 0 | 约 0 | 3.09 g/s |

SMA 两个阶段的压力输出分别达到 `-0.0286 MPa` 和 `-0.0454 MPa`，但旧模板 Saturation 仍把输出截断到 `-0.02 MPa`。因此上一组流量不足不是热量赋值导致，而是压力限幅导致。

### 放开压力下限后的真实一循环

输出目录：
`gx101r1_R69_remote/outputs/heatdrive_ecc_qian2019_3cycle/qian2019_table2_table4_simscape_1cycle_20260730_105617`

| 阶段 | SMA 流量 | SE Stage 2 流量 | SE Stage 4 流量 |
|---|---:|---:|---:|
| 1 | 27.50 g/s | 约 0 | 约 0 |
| 2 | 约 0 | 1.62 g/s | 约 0 |
| 3 | 34.22 g/s | 约 0 | 约 0 |
| 4 | 约 0 | 约 0 | 3.09 g/s |

实际命令输出分别约为 `-0.0286 MPa`、`-0.0454 MPa`，说明该组仍未使用目标压力值；因此下一组将检验 `-0.098/-0.100 MPa`。

## 已发现的物理问题

在高流量边界试验中，物理探针 `probe_sma_stage1_v1_pump_side_T_K` 最低约 `272.666 K`，SHEX 返回支路最低约 `274.445 K`。Simscape 同时报告三通、阀门和 SMA 压力源的水温低于有效物性范围。

这不是可接受的成功结果，也不是通过钳位温度解决的问题。需要继续检查：

1. V1/V2 与 SHEX buffer 的零流量支路是否发生反向混合；
2. SHEX 等效热容和 SMA constitutive 热源的能量符号及连接方向；
3. 高流量下等效管段体积、热液体初值和阀门关断后的滞留流体状态；
4. 每阶段入口/出口能量守恒和所有热液体探针的有效范围。

在上述问题解决前，不宣称 Qian Table 4 流量或性能复现通过。

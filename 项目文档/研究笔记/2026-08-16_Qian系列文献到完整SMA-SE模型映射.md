# Qian 系列文献到完整 SMA-SE 模型映射

更新日期：2026-08-16

## 模型边界

当前唯一生产模型为
`gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx`。目标是复现 Qian 2019
Table 4 的单效热驱动弹热制冷系统，不把独立 SE 逆循环的 690 MPa 规定应力轨迹
带入完整系统，也不把 2023 双效系统误并入当前单效拓扑。

## 文献分工

- Qian et al., Energy 182 (2019), *A heat driven elastocaloric cooling
  system*：当前系统的主基准。提供四阶段流路、SMA-SE 式 (5)-(8)、材料
  Table 2、成品几何和运行参数 Table 4、式 (9)-(10) 性能定义。
- Tan et al. (2020), *Thermodynamic cycle analysis of heat driven
  elastocaloric cooling system*：用于等力、等位移、质量比、最小驱动温差和 COP
  边界复核；它是准平衡分析，不能替代瞬态 Simulink 求解。
- Yuan et al., Applied Thermal Engineering 218 (2023), *Numerical study of
  a double-effect elastocaloric cooling system powered by low-grade heat*：附录
  (A1)-(A8) 再次给出一维固液能量方程、本构、等力和等位移约束，并明确每个
  1 ms 步内联立 ODE 与代数方程。当前只采用其数值实现证据，不采用双效拓扑或
  150 degC 工况。
- Qian et al. (2017), *Numerical modeling of an active elastocaloric
  regenerator refrigerator with phase transformation kinetics...*：提供一维离散、
  局部相分数、均匀轴向应力、MAS 动力学形式和 Nu 入口修正。其 NiTi 的 Af/Mf、
  相变应变和松弛时间属于另一材料集，不能直接覆盖 2019 Table 2。
- Qian et al. (2015), *Study on high efficient heat recovery cycle for
  solid-state cooling*：用于连接管热容、轴向导热、有限流体库存和热回收不可逆性
  审核，不把独立热回收试验的 15 s 时序移植到本系统。

## 当前单效四阶段

1. 0-3.5 s：SHEX 水路连续流经 SMA；SMA M->A 收缩，实时加载 SE A->M。
2. 3.5-5.0 s：SMA 仍保持 SHEX 水路；CHEX glycol 经过同一 SE 床流向 HHEX。
3. 5.0-8.5 s：HHEX 独立水路连续流经 SMA；SMA A->M，实时卸载 SE M->A。
4. 8.5-10.0 s：SMA 仍保持 HHEX 水路；HHEX glycol 反向经过同一 SE 床流向
   CHEX。

SMA-water 与 SE-glycol 在 HHEX 中只共享热端热容，不发生流体混合。Stage 2/4
是同一 SE 床内流体反向，不是两套可独立重置的 21 节点流体状态。

## 机械联立

每个轴向节点保存温度和相分数；同截面材料采用均匀应力。移动梁给出全床约束：

`sigma_SMA*A_SMA = sigma_SE*A_SE`

`L_SMA*mean(epsilon_SMA) = L_SE*mean(epsilon_SE)`

`epsilon_SE = epsilon_T_SE*xM_SE + sigma_SE/E_SE`

`epsilon_SMA = epsilon_T_SMA*(1-xM_SMA) - sigma_SMA/E_SMA`

由于当前弹性模量为常数，上述代数系统有闭式解；闭式求解与 Trust-Region 解在该
特例下等价，但必须在每个动力学子步重新计算。2026-08-16 起，相分数按固定
1 ms Bogacki-Shampine ODE3 三个子阶段推进，每个子阶段都重新求解兼容应力，
不再使用一阶显式欧拉。

## 参数边界

材料参数来自 2019 Table 2；成品几何和流量来自 2019 Table 4。因此成品基准是
32 根直径 1 mm SMA 线、两块 0.5 x 17 mm SE 板、SMA/SE 质量比 3.2、SMA
50.8 g/s、SE 3.2 g/s、5 s 热半周期、5 s 冷半周期、0.1 Hz、Tg=120 degC、
Th=30 degC。Table 2 的 8 根 1.5 mm 线和 0.2 x 10 x 200 mm 板只用于论文前段
算例，不得与 Table 4 的 26.2 K/0.64 W/g 成品结果混用。

2019 未报告完整 MAS 激活体积、端点 UA、glycol-water 浓度和全部附件热容。
这些量必须作为显式工程闭合做敏感性分析，不能按 26.2 K 反标。2017 论文给出
的 0.01 s 松弛时间属于不同 NiTi 材料集，目前只作候选敏感性边界，不直接写入
生产参数。

## 当前失效边界

旧 ODE-Euler/降阶动力学长链运行到 cycle 160 时，SE 相变摆幅降至 0.972248，
最后十循环完整状态仍明显漂移，Eq. (9) 瞬态温跨已越过 26.2 K。该结果证明
“达到目标温跨”不等于周期稳态，也不能继续作为成品性能。后续必须从冷启动用
修正后的数值积分和显式轴向几何重新完成 1-cycle、3-cycle，再决定是否进入新的
长循环。

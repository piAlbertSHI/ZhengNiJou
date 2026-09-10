# Qian 系列文献对照定位与 SMA-SE 模型映射报告

更新日期：2026-09-11

## 使用边界

本报告只整理本地 PDF 的定位和模型映射，不把文献数值当作当前模型的验证结果。
Qian 2019 是当前单效 SMA-SE 热驱动系统的唯一 Table 4 定量合同；其他文献只作
方程、控制体、热回收、周期稳态和参数边界的辅助对照。

## 主合同：Qian et al. (2019)

本地文件：`C:\Users\86182\Desktop\冷凝文献\弹热制冷文献\A heat driven elastocaloric cooling system..pdf`

| 文献位置 | 对照内容 | 当前模型用途 |
|---|---|---|
| PDF 3-4，Fig. 1 | SMA、SE、SHEX/HHEX/CHEX、四阶段流路 | 检查单效正逆热驱动拓扑与阶段时序 |
| PDF 5，Eqs. (1)-(4) | 固液能量方程、相分数动力学 | 对照轴向节点、换热和有限速率相变 |
| PDF 5，Eqs. (5)-(8) | 等力、等位移机械兼容 | 每个动力学子步重新求解 SMA-SE 兼容应力 |
| PDF 5，Eqs. (9)-(10) | 温跨、冷量和 SCP 定义 | 只在共同末周期窗口、统一质量基准下计算 |
| PDF 6，Table 2 | 材料参数和前段算例 | 不能与 Table 4 成品几何混用 |
| PDF 15-16，Fig. 13 | 成品装置和几何说明 | 对照 32 根 1 mm SMA 线和 SE 板 |
| PDF 16-17，Table 4 | 26.2 K 与 0.64 W/g 两个边界 | 必须分别求 zero-load、zero-lift 后再成对审核 |

## 辅助文献定位

| 文献 | 本地 PDF 位置 | 可用于当前模型的范围 |
|---|---|---|
| Tan et al. (2020), Energy 197, 117261 | PDF 6：Eqs. (1)-(2)；PDF 7-9：Eqs. (5)-(16)；PDF 18-20：Figs. 9-10 | 等力/等位移、质量比、回热和权衡分析；不替代瞬态 Simscape |
| Qian et al. (2015), IJ Refrigeration 56, 65-80 | PDF 4：循环类型；PDF 6-8：系统控制体；PDF 9：Table 2/PID；PDF 10：cyclic steady | 控制体、流体库存、周期稳态定义和系统边界 |
| Qian et al. (2017), Energy 141, 744-756 | PDF 5：AER/离散；PDF 6：10-cycle 收敛；PDF 9-10：matching principle | 相变动力学、轴向离散、有效域和网格审核 |
| Qian et al. (2015), IJ Refrigeration 55, 102-119 | PDF 3-4：Figs. 1-2；PDF 6-8：回热效率；PDF 13-17：参数影响 | 回热、附件库存和跨阶段状态继承；不直接移植时序 |
| Qian et al. (2023), Applied Thermal Engineering 219, 119540 | PDF 3：Fig. 1/Table 1；PDF 4-5：COP关系；PDF 9-12：循环比较 | 区分材料级、循环级和系统级性能边界 |

## 当前对照结论

当前模型仍没有通过固定 `Tc` 的完整冷态机制、周期、流量和能量门禁，因而不能声称
`validated` 或 `reproduced`。文献对照中允许使用 `simulated`、`predicted`、
`benchmark-consistent` 和 `not yet reproduced`。任何当前结果若缺少共同参数合同、共同
末周期窗口或完整控制体闭合，只能作为诊断证据。

## 权威索引

更完整的逐页记录见：
`C:\Users\86182\Desktop\正逆耦合\项目文档\研究笔记\2026-09-03_Qian本地文献精确定位与模型映射.md`

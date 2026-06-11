# Agent2 第六轮失败复现与四支路修复依据

生成时间：2026-06-11

## 1. 第五轮失败必须继承为第六轮起点

第五轮不是验收通过版本。已确认的硬失败如下：

| 项目 | 第五轮证据 | 第六轮要求 |
|---|---:|---|
| SHEX 动态输入 | 1-cycle `SHEX_input_J = 0` | 必须由独立 `SMA_SHEX` 支路边界和流体焓差积分得到 |
| SMA 升温 | Stage1 `Ta: 308 -> 308.039945 K` | Stage1 必须明显升温，热量量级接近论文 `Qh` |
| 相变状态 | `xM_a = 1`、`xM_r = 0` 全程不动 | 相分数必须由温度、应力、驱动力和时间积分推进 |
| Eq.6/Eq.7 | residual 为 0 但应力/相变退化 | 必须在非零应力、非零相变状态下通过 |
| 能量闭合 | cycle relative residual `3.47153848245893` | 必须定位到固体、潜热、机械功和四支路能量项 |
| 求解稳定性 | Stage1 0.02 s 预检 600 s 超时；swap-route 在 `HotPipe` 不收敛 | 第六轮每个诊断仿真必须有 wall-time 上限，失败即停 |

第六轮不能通过调图、调报告或常数填表解决这些问题。

## 2. 第五轮代码中必须删除的代理口径

第五轮能量审计中存在不可作为第六轮结果的代理写法：

- `q_shex = q_sma_hold`
- `PECC_dynamic_W = Qr_dynamic_W`
- 论文 `Qh/Qr/PECC/etaECC` 常数作为动态结果
- 固体平均温度冒充流体出口
- reservoir boundary 冒充 internal temperature

第六轮能量表只允许来自：

- Simulink/Simscape 真实流体探针；
- 真实 `m_dot * cp * (T_in - T_out)`；
- branch boundary heat flow 或支路储能积分；
- 51 节点固体温度、相分数和本构输出；
- 应力、应变、力/位移或等效机械功积分。

## 3. d_2.slx 可迁移本构思想

`d_2.slx` 中可迁移的不是硬编码 12+12 节点参数，而是以下求解思想：

1. 驱动 SMA 与制冷 SE 初始相态分离：
   - SMA 初始 martensite fraction 为 1；
   - SE 初始 martensite fraction 为 0。
2. `xi_state` 使用持久状态推进，而不是每步重置。
3. 相变驱动力 `pai` 由应力、温度、熵变项和相变抗力组成。
4. 相变速率 `r_xi` 由 `pai/Y` 的幂律或阈值控制，并积分得到 `xi_state`。
5. 潜热 `q` 由相变速率、节点体积和材料热项计算。
6. 泵/阀信号应服从相态和阶段逻辑，而不是直接指定目标相分数。

第六轮禁止沿用 d_2 中的错误近似：

- 12+12 节点硬编码；
- 强制温度隔离；
- 800 MPa 固定加载；
- target 相分数或强制截断制造结果；
- 只更新某一个节点后复制到全体节点。

## 4. 第六轮目标拓扑

第六轮必须有四个独立物理角色支路：

| 支路 | 活动阶段 | 目标热边界 | 与固体接口 | 必测动态量 |
|---|---|---|---|---|
| `SMA_SHEX` | Stage1 | `Th` / SHEX 废热源 | SMA 51 节点 | `m_dot`、`T_in`、`T_out`、`Q_SHEX_boundary` |
| `SMA_THE` | Stage3 | `T0` 环境热汇 | SMA 51 节点 | `m_dot`、`T_in`、`T_out`、`Q_SMA_to_THE` |
| `SE_THE` | Stage2 | `T0` 环境热汇 | SE 51 节点 | `m_dot`、`T_in`、`T_out`、`Q_SE_to_THE` |
| `SE_RHE` | Stage4 | `Tc` 冷负载/RHE | SE 51 节点 | `m_dot`、`T_in`、`T_out`、`Q_RHE_to_SE` |

四条支路必须是独立实例，不能让同一 `HotPipe` 或同一成熟支路跨阶段承担相反热角色。

## 5. 分层验证门槛

第六轮执行顺序：

1. 第五轮失败复现和记录。
2. 构建 `heatdrive_ecc_four_branch_physical.slx`，不覆盖 mature 原模型和第五轮失败模型。
3. 四支路结构检查：四个支路实例、探针、阶段命令和热边界均存在。
4. 支路单元预检：
   - 0.02 s；
   - 0.1 s；
   - full-stage；
   - 任一 0.02 s 超过 120 s wall time 即失败并停止。
5. 机械/本构离线预检：
   - `Ta: 308 -> 340.412 K`，检查 `xM_a` 下降、`xM_r` 上升；
   - `Ta: 340.412 -> 308 K`，检查卸载方向；
   - 输出 sigma、epsilon、Eq.6/Eq.7、latent heat、mechanical work。
6. Stage1 full 通过后，才允许 Stage2/3/4 单阶段闭合。
7. 四个单阶段闭合通过后，才允许 1-cycle。
8. 1-cycle 通过后，才允许 3-cycle。
9. 3-cycle 通过后，才允许 10-cycle。

## 6. 第六轮当前第一批 hard checks

| hard check | 状态 |
|---|---|
| 第六轮分支创建 | PASS |
| 必读第五轮失败报告 | PASS |
| 必读第六轮修复依据 | PASS |
| 必读第五轮拓扑与映射表 | PASS |
| `d_2.slx` 本构核心只读检查 | PASS |
| 新模型不覆盖 mature 和第五轮模型 | 待执行 |
| 四支路独立实例 | 待执行 |
| 支路预检 | 待执行 |
| 机械预检 | 待执行 |
| 1-cycle / 3-cycle / 10-cycle | 待执行 |


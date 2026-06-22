# SMA侧Stage1/3探针与SHEX状态核查报告

日期：2026-06-22

## 修改范围

- 主模型：`gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx`
- 生成/集成脚本：`gx101r1_R69_remote/Integrate_HeatDriveECC_Constitutive21_Interface.m`
- 本轮只在现有主模型上补齐左侧SMA侧观测与排版，不新建新的主`.slx`文件。

## SHEX buffer状态逻辑

- `Build_Simulink_Exchange_Params.m`中已有`shex_fluid_buffer_T_init`参数，默认由`hot_sink_T_init`给出。
- 主模型中的`SHEXFluidBuffer`使用该参数作为初始温度`T_I`。
- 当前四阶段方案正在转向一次连续Simulink运行，因此SHEX buffer在同一次仿真中由Simscape状态自然延续，不需要每个阶段重启后再手动写回。
- 需要保留的限制：如果未来改回四阶段分段重启Simulink，则`Run_Simulink_Exchange_Hook`还需要显式读取并传递SHEX buffer末态；本轮未改成分段重启逻辑。

## 新增探针

左侧SMA Stage 1/3根层流路新增温度探针：

- `probe_root_shex_buffer_fluid_T_K`
- `shex_buffer_temp_out`
- `probe_sma_stage1_v1_shex_side_T_K`
- `probe_sma_stage1_v1_pump_side_T_K`
- `probe_sma_stage13_pump_outlet_T_K`
- `sma_stage1_inlet_fluid_temp_out`
- `probe_sma_stage1_port1_v3_side_T_K`
- `sma_stage1_outlet_fluid_temp_out`
- `probe_sma_stage1_port2_v5_side_T_K`
- `probe_sma_stage1_v5_shex_side_T_K`
- `probe_sma_stage3_v2_hhex_side_T_K`
- `probe_sma_stage3_v2_pump_side_T_K`
- `sma_stage3_inlet_fluid_temp_out`
- `probe_sma_stage3_port3_v4_side_T_K`
- `sma_stage3_outlet_fluid_temp_out`
- `probe_sma_stage3_port4_v6_side_T_K`
- `probe_sma_stage3_v6_hhex_side_T_K`

HHEX内部SMA独立分支新增温度探针：

- `hhex_sma_branch_inlet_fluid_temp_out`
- `hhex_sma_branch_outlet_fluid_temp_out`

复核结果：

- ToWorkspace总数：77
- ToWorkspace变量唯一数：77
- 上述19个新增观测变量均存在且均只出现一次。

## 排版与截图检查

已重新排布：

- 左侧SMA Stage 1/3根层主要阀门、泵、SHEX buffer、SMA、SHEX与探针输出块。
- SMA/SE内部21节点本构热源列，修复了前一版热源块之间的重叠。
- HHEX内部新增SMA分支入口/出口探针的位置。

截图输出在：

- `gx101r1_R69_remote/outputs/default_run/stage13_root_with_probes.png`
- `gx101r1_R69_remote/outputs/default_run/sma_subsystem21_with_constitutive_sources.png`
- `gx101r1_R69_remote/outputs/default_run/hhex_sma_branch_probes.png`

内部重叠脚本检查：

- SMA/Subsystem2：本构热源列无重叠；剩余7处为原21节点传导块`NodeCond_*`的继承式贴近排布。
- SE/Subsystem2：同上，说明这不是本轮新增SMA侧热源列造成的额外问题。

## 短时接口冒烟测试结果

运行参数：

- `cycle_count = 1`仅用于取得当前默认`StopTime`，不代表已经完成文献尺度或原24阶段尺度的完整物理循环。
- `StopTime = 1.59447513812155 s`
- 输出文件：`gx101r1_R69_remote/outputs/default_run/one_cycle_probe_check.mat`

仿真检查：

- SimulationOutput变量数：80
- 期望观测变量缺失数：0
- 新增SMA/SHEX/HHEX探针均有713个时间点，终止时间覆盖到`1.59447513812155 s`。
- 该结果只证明新增接口、探针和状态输出在短时默认工况下可执行，不能作为“完整1循环已经跑通”的结论。

主要温度范围：

- SHEX buffer：`307.967 K` 到 `308.002 K`
- SMA Stage 1入口：`308.004 K` 到 `308.075 K`
- SMA Stage 1出口：`308.000 K` 到 `308.092 K`
- SMA Stage 3入口：`308.004 K` 到 `308.075 K`
- SMA Stage 3出口：`308.000 K` 到 `308.092 K`
- HHEX SMA分支入口：`308.000 K` 到 `308.010 K`
- HHEX SMA分支出口：`306.983 K` 到 `308.000 K`

## 当前限制

- 本轮验证了左侧SMA侧流路观测、SHEX buffer连续仿真状态、HHEX SMA分支探针和短时默认工况可运行性。
- 但当前1 cycle中`ECC_Q_SMA_constitutive_W`和`ECC_Q_SE_constitutive_W`仍为0，说明本构热源在此算例中尚未产生有效热功输入。
- 因此本轮结果不能解释为正逆耦合弹热热源已经物理闭环，只能作为下一步“本构加载/卸载热源真正接入Stage 1/3与Stage 2/4”的接口和观测基础。

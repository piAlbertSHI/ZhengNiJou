# gx101r1_R69_remote 运行与接手说明

本文件夹是 gx101r1 当前主线的轻量远程运行包。它用于在本机或远程电脑上并行运行多工况长循环，不依赖历史任务书、旧验证脚本、Git 元数据或过往 Output 结果。

当前包的主线语义：

- 模型：`nixunhuan_solver101_internal.slx`
- 后端：Simulink/Simscape directional 101-node exchanger
- 控制：R42/R44 pressure PI feedback
- 冷端：R69 symmetric cold-end topology
- SMA pipe 热容：`sma_pipe_internal_volume_target_ml = 0.1`
- SMA pipe 初始温度策略：`same_path_carryover`
- 热端散热：`hot_sink_ambient_G_W_per_K = 30`
- 求解：`accelerator + ode23t`
- 输出目录：本包内 `Output\<run_id>\<case_tag>\`

不要把整个历史 gx101r1 工作区复制到每个工况。并行运行时，每个工况只需要独立 `Output` 子目录、独立 `MATLAB_PREFDIR`、独立 `TEMP/TMP`、独立 `codegen/cache`。

## 目录结构

```text
gx101r1_R69_remote\
  *.m                                  # 主循环、Simulink hook、参数、绘图、汇总函数
  *.slx                                # 当前模型和模板
  *.ps1                                # 远程启动、监控、汇总、COP 后处理脚本
  Tools\validation\Remote_RunCase.m    # 远程生产 runner
  Output\                              # 运行结果；可删除或另存，不属于源码
```

推荐远程路径：

```powershell
E:\gx101r1_R69_remote
```

路径和 case 名保持短。Simulink 对路径长度敏感，长路径会增加加载和 codegen 失败风险。

## 环境要求

必须安装：

- MATLAB R2025b 或兼容版本
- Simulink
- Simscape
- Simscape Fluids
- Simulink Coder，license feature 名为 `Real-Time_Workshop`
- PowerShell 中可直接调用 `matlab`

快速检查：

```powershell
matlab -batch "disp(version); disp(license('test','Simulink')); disp(license('test','Simscape')); disp(license('test','Simscape_Fluids')); disp(license('test','Real-Time_Workshop'))"
```

如果 `matlab` 命令不可用，把 MATLAB bin 目录加入 PATH，或在启动脚本中把 `matlab` 改成完整路径，例如：

```powershell
"C:\Program Files\MATLAB\R2025b\bin\matlab.exe"
```

## 运行链路

典型调用链：

```text
PowerShell
  -> Launch_OneCase.ps1
    -> 每个 case 写 run_case.m / run_case.ps1
    -> matlab -batch run_case.m
      -> Tools\validation\Remote_RunCase.m
        -> Run_GlobalXi_Simulink_Cycles.m
          -> stage1 load: GlobalXi_TimeStep_Core.m
          -> stage2 hold exchange: Run_Simulink_Exchange_Hook.m + Simulink .slx
          -> stage3 unload: GlobalXi_TimeStep_Core.m
          -> stage4 cooldown exchange: Run_Simulink_Exchange_Hook.m + Simulink .slx
        -> Build_GlobalXi_Run_Validation_Summary.m
        -> Summarize_GX101R1_NoLoad_Energy_Table.m
        -> optional plot functions
```

`Launch_OneCase.ps1` 不复制源码。它只在每个 case 下创建：

```text
pref\
tmp\
logs\
codegen\cache\
run_case.m
run_case.ps1
run_options_input.json
run_options_input.mat
```

这就是当前 fast/parallel 规则的核心：源码共享，运行状态隔离。

## 固定求解设置

`Tools\validation\Remote_RunCase.m` 写死当前主线设置：

```text
simulation_mode = accelerator
prewarm_accelerator_cache = false
allow_simulation_mode_fallback_to_normal = false
simulink_solver = ode23t
RelTol = 1e-2
AbsTol = 1e-3
MaxStep = 0.4
InitialStep = auto
ZeroCross = on
Simscape local solver = off
Fast Restart = off
SimState = off
daessc = off
Rapid Accelerator = off
max_attempts = 1
compensation = disabled
reused fallback = disabled
probe_sample_count = 50
```

不要在长循环生产 run 中启用 compensation/reused。触发 compensation 或 reused 的结果不能作为 winner。

## 单工况运行

在远程电脑 PowerShell 中执行：

```powershell
$repo = "E:\gx101r1_R69_remote"
Set-Location -LiteralPath $repo

powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\Launch_OneCase.ps1" `
  -RepoRoot $repo `
  -RunId "single_v050_t240_30c" `
  -VStar 0.5 `
  -StageTime 2.4 `
  -NCycles 30 `
  -SavePlots
```

输出：

```text
E:\gx101r1_R69_remote\Output\single_v050_t240_30c\v050_t240_30c\
```

注意：`Launch_OneCase.ps1` 没有 `-CaseTag` 参数。case 子目录名自动生成：

```text
v{VStar*100三位数}_t{StageTime*100三位数}_{NCycles}c
```

例如：

```text
V*=0.5, t=2.4, 30 cycle -> v050_t240_30c
V*=1.0, t=0.4, 50 cycle -> v100_t040_50c
```

## 多工况并行运行

示例：固定 `t=2.4s`，并行跑 8 组 30-cycle。

```powershell
$repo = "E:\gx101r1_R69_remote"
$batch = "r73_v020_v100_t240_30c_" + (Get-Date -Format "MMdd_HHmm")
Set-Location -LiteralPath $repo

$cases = @(0.2, 0.3, 0.4, 0.6, 0.7, 0.8, 0.9, 1.0)

foreach ($v in $cases) {
  powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\Launch_OneCase.ps1" `
    -RepoRoot $repo `
    -RunId $batch `
    -VStar $v `
    -StageTime 2.4 `
    -NCycles 30 `
    -SavePlots
  Start-Sleep -Seconds 3
}

Write-Host "Started batch: $repo\Output\$batch"
```

示例：固定 `V*=0.5`，扫 `t=0.9/1.4/1.9/2.4/2.9/3.4/3.9`，每组 30-cycle。

```powershell
$repo = "E:\gx101r1_R69_remote"
$batch = "r73_v050_tscan_30c_" + (Get-Date -Format "MMdd_HHmm")
Set-Location -LiteralPath $repo

$times = @(0.9, 1.4, 1.9, 2.4, 2.9, 3.4, 3.9)

foreach ($t in $times) {
  powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\Launch_OneCase.ps1" `
    -RepoRoot $repo `
    -RunId $batch `
    -VStar 0.5 `
    -StageTime $t `
    -NCycles 30 `
    -SavePlots
  Start-Sleep -Seconds 3
}

Write-Host "Started batch: $repo\Output\$batch"
```

推荐 worker 数：

- 本机：4 个左右比较稳。
- 64 核 / 200GB 内存远程机：先开 8 个 worker。
- 需要 12 个以上 worker 时，先做 1-cycle smoke，确认没有统一冷启动/路径/缓存问题，再开长循环。

并行不是 MATLAB parpool。当前方式是多 MATLAB 进程并行，每个进程独立 pref/tmp/codegen cache。

## 监控运行

查看最新 batch：

```powershell
$repo = "E:\gx101r1_R69_remote"
$batch = Get-ChildItem "$repo\Output" -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty Name

powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\Monitor_Batch.ps1" `
  -RepoRoot $repo `
  -BatchDir "$repo\Output\$batch"
```

监控重点：

- `summary.json` 是否存在
- `stages.csv` 是否存在
- `runner_error.txt` / `matlab_error.txt` 是否存在
- `logs\powershell_stderr.log` 是否非 0
- 当前 checkpoint 是否继续增长

不要因为某个 stage 超过几分钟就直接 kill。部分低 V 或长 t 的 stage 可能很慢。只有明确出现错误文件、进程退出、或长时间没有任何文件更新时间时，再做故障处理。

## 汇总 batch

```powershell
$repo = "E:\gx101r1_R69_remote"
$batch = Get-ChildItem "$repo\Output" -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty Name

powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\Collect_Batch.ps1" `
  -RepoRoot $repo `
  -BatchDir "$repo\Output\$batch"
```

输出：

```text
Output\<batch>\batch_summary.csv
Output\<batch>\batch_summary.md
```

## COP 汇总

批量计算 30-cycle 结果的 COP：

```powershell
$repo = "E:\gx101r1_R69_remote"
Set-Location -LiteralPath $repo

powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\Compute_COP_Summary.ps1" `
  -RepoRoot $repo `
  -OutputRoot "$repo\Output" `
  -MinCycles 30
```

输出在：

```text
Output\cop_summary_YYYYMMDD_HHMM\
  cop_summary.csv
  cop_summary.md
  cop_summary_skipped.csv
```

COP 字段含义：

- `COP_no_pump = Qcool / W1`
- `COP_eq14_measured = Qcool / (W1 + measured Wpump)`，当前 PI 模式通常为 `NaN`，因为没有真实压力输出探针。
- `COP_lower_bound = Qcool / (W1 + saturation-bound Wpump)`，用 PI pressure min/max 给泵功保守上限。
- `SCP_W_per_kg` 使用当前结果内的 Qcool、周期和 SMA 质量字段。

当前泵功处理是后处理估算，不需要为了 COP 初筛重跑全部长循环。

## 常用结果文件

每个 case 目录下常见文件：

```text
summary.json / summary.md              # 单工况总览
stages.csv                             # 每 stage walltime、flush、关键诊断
result.mat                             # run_options + run_result，大文件
run_result.mat                         # run_result 快速读取
cycle_summary.mat                      # cycle 级摘要
cycle_diagnostics.json                 # cycle 级诊断
validation_summary.json                # validation policy 输出
no_load_energy_table.csv/json/mat      # no-load 能量表
state_sync_trace_table.csv/json/mat    # stage 间状态写回追踪
figures\                               # SavePlots 时生成
checkpoints\                           # stage checkpoint
logs\powershell_stdout.log
logs\powershell_stderr.log
matlab_diary.txt
runner_error.txt                       # MATLAB runner 捕获异常时出现
matlab_error.txt                       # Launch wrapper 捕获异常时出现
```

判断 flush 是否合格：

```text
stage2: actual_active_flush_volume_ratio / V* 应在目标范围内
stage4: actual_active_flush_volume_ratio / V* 应在目标范围内
```

近期放宽标准为 `0.90-1.10`。例如 `V*=0.5` 时，raw flush 在 `0.45-0.55` 合格。

## 文件清单

以下说明覆盖本包内非 Output 文件。`Output` 是结果目录，不属于源码。

### PowerShell 脚本

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `Launch_OneCase.ps1` | 单工况启动器。创建独立 case 目录、pref/tmp/logs、`run_case.m`、`run_case.ps1`，然后后台启动一个 MATLAB。 | 所有远程/本机并行都通过它启动。参数是 `RepoRoot`、`RunId`、`VStar`、`StageTime`、`NCycles`、`SavePlots`。 |
| `Monitor_Batch.ps1` | 扫描 batch 内各 case 状态。 | 用于查看 summary、错误文件、stderr、checkpoint 进度。不会启动或杀进程。 |
| `Collect_Batch.ps1` | 汇总一个 batch 的 case 结果。 | 读取每个 case 的 summary/stages，生成 batch 级 CSV/MD。 |
| `Compute_COP_Summary.ps1` | 汇总多组完成结果的 COP/SCP。 | 扫描 `Output` 下 result，跳过未达到 `MinCycles` 的 case。 |

### 远程 runner

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `Tools\validation\Remote_RunCase.m` | 远程生产 runner。设置当前主线 exchange options，调用 `Run_GlobalXi_Simulink_Cycles`，写 `summary.json`、`stages.csv`、能量表和图。 | `Launch_OneCase.ps1` 自动调用。若要改变默认物理/求解配置，优先改这里，但改动必须可追踪。 |

### Simulink 模型

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `nixunhuan_solver101_internal.slx` | 当前主线 Simulink/Simscape 101-node internal exchanger。 | `Remote_RunCase` 默认使用它。不要在远端长跑时手动打开并保存。 |
| `nixunhuan_singal.slx` | 历史/模板相关模型文件。 | 构建链和旧模板可能引用。正常远程长跑不直接打开。 |
| `nixunhuan_solver101_internal.slx.autosave` | Simulink 自动保存文件。 | 不是运行必需文件。若模型异常损坏，可人工参考，但不要当主模型运行。 |

### 主循环与 stage 控制

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `Run_GlobalXi_Simulink_Cycles.m` | 四阶段多 cycle 主循环。负责 stage 顺序、checkpoint、runtime、summary、plot 调用。 | `Remote_RunCase` 的核心入口。 |
| `Run_GlobalXi_Simulink_Cycle_Main.m` | 本地/主工作区手动运行入口。 | 远程轻量包一般不用；保留用于 MATLAB 内直接启动。 |
| `Build_FourStage_Cycle_Schedule.m` | 生成 load、hold exchange、unload、cooldown exchange 四阶段 schedule。 | 被主循环调用，决定每个 stage 的物理角色和时间。 |
| `Resolve_Exchange_Stage_Config.m` | 把 stage 信息解析成 Simulink stage config，包括阀门、stop time、active path。 | `Run_Simulink_Exchange_Hook` 前置配置。 |
| `Create_Simulink_Exchange_Runtime.m` | 创建 runtime 容器和目录结构。 | 主循环用它维护 checkpoints、outputs、model path 等。 |
| `Save_Stage_Checkpoint.m` | 保存 stage checkpoint。 | 每个 stage 结束后由主循环调用。 |

### Simulink hook、模型构建与参数

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `Run_Simulink_Exchange_Hook.m` | stage2/stage4 的 Simulink-backed thermal hook。负责参数注入、仿真调用、探针读取、流量/能量审计、状态写回。 | 这是换热 stage 的主逻辑文件。 |
| `Build_Simulink_Exchange_Params.m` | 将当前 state、stage config、exchange options 转成 `.slx` 所需 workspace 参数。含 V/t、PI 调度、sink/buffer/pipe 参数。 | `Run_Simulink_Exchange_Hook` 每个 Simulink stage 调用。 |
| `Build_Simulink_Exchange_Model.m` | 程序化构建/重建 exchange `.slx` 的模型函数。 | 远程生产 run 默认 `force_rebuild_model=false`，一般不调用重建。结构大改时才用。 |
| `Build_nixunhuan_solver101_internal.m` | 包装构建当前 internal 101-node 模型。 | 调用 `Build_Simulink_Exchange_Model`。正常远程长跑不强制 rebuild。 |
| `Generate_GX101R1_Thermal_Object_Contract.m` | 生成 hot/cold thermal object contract。 | 静态 contract/audit 用，生产 run 不直接依赖。 |
| `Validate_GX101R1_Static_Contract.m` | 零仿真静态 contract 检查。 | 修改模型或 contract 后用于确认结构/字段。 |
| `Validate_GX101R1_Split_Exchange_Stage.m` | 分段 exchange stage 验证工具。 | 历史验证/诊断用。 |
| `Validate_GX101R1_Split_Stage4.m` | stage4 split 验证工具。 | 历史验证/诊断用。 |

### SMA/GlobalXi 物理核心

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `GlobalXi_TimeStep_Core.m` | adiabatic loading/unloading 的核心求解器，含材料/力学/温度/相变变量更新。 | stage1/stage3 调用。 |
| `Run_GlobalXi_Time_Loading_Prototype.m` | loading wrapper。 | 主循环 stage1 使用。 |
| `Run_GlobalXi_Unloading_Prototype.m` | unloading wrapper。 | 主循环 stage3 使用。 |
| `Run_GlobalXi_Cooled_Unloading_Prototype.m` | 冷却后 unloading 原型。 | 诊断/历史用途。 |
| `SMA_LocalKinetics.m` | SMA 本构局部 helper。 | GlobalXi 核心调用。不要随意改动材料公式。 |
| `Build_GlobalXi_Checkpoint_From_Exchanged_T.m` | 用换热后的 51-node 温度重建 GlobalXi checkpoint。 | exchange stage 后状态衔接。 |
| `Build_GlobalXi_Restart_Balance_Checkpoint.m` | exchange 后 restart balance。 | stage 边界物理重启/残差平衡。 |
| `Solve_GlobalXi_Exchange_Restart_Balance.m` | 求解 exchange restart equilibrium。 | 配合 restart balance checkpoint。 |
| `GlobalXi_Checkpoint_To_Simulink_State.m` | 将 GlobalXi checkpoint 转成 Simulink hook 输入 state。 | stage2/stage4 前使用。 |

### 51/101 几何映射

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `Build_Diameter_Strip_Geometry.m` | 构建 101-strip proxy geometry。 | 51/101 映射与 directional strip 使用。 |
| `Initialize_Directional_Strip_State.m` | 从 51-node radial state 初始化 101-strip directional state。 | Simulink 101-node exchange 前使用。 |
| `Map_Radial51_To_Diameter101.m` | 将 51-node 径向温度映射到 101-node 直径方向。 | 进入 directional fluid exchange 前使用。 |
| `Compress_Diameter101_To_Radial51.m` | 将 101-node exchange 结果压缩回 51-node radial solver。 | exchange stage 后回写 SMA 温度。 |
| `Build_Directional_Strip_Contract.m` | 为某个 stage 生成 directional 101-strip exchange contract。 | 辅助定义 active direction 和映射约束。 |

### 报告、验证与表格

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `Build_GlobalXi_Stage_Report.m` | 固定 schema 的单 stage report。 | 主循环用它统一记录 walltime、flush、能量、PI、探针等字段。 |
| `Build_GlobalXi_Run_Validation_Summary.m` | run-level validation summary。 | `Remote_RunCase` 生成 `validation_summary.json`。 |
| `Build_GX101R1_State_Sync_Trace_Table.m` | 输出每 stage side-state source/writeback trace。 | 追踪 cold/hot sink、buffer、pipe 状态继承。 |
| `Build_GX101R1_Continuous_Probe_Timeline.m` | 将 stage 级 50 点探针拼接成全局时间曲线。 | 绘图函数调用。 |
| `Summarize_GX101R1_NoLoad_Energy_Table.m` | 从 `result.mat` 生成 no-load 能量表。 | `Remote_RunCase` 自动调用。 |

### 绘图

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `Plot_GlobalXi_Simulink_Cycle_Results.m` | 主绘图函数，生成 cycle、SMA、sink、transport 等图。 | `SavePlots` 时由 runner 调用，也可手动传入 `run_result`。 |
| `Plot_GX101R1_NoLoad_Literature_Style.m` | no-load 文献风格图，含 sink envelope、Zhou-style outlet 等。 | 长循环结果分析时重点使用。 |
| `Plot_GX101R1_Fixed_Probe_Trajectories.m` | 固定探针全局时间轨迹。 | 用于查看 CHEX/HHEX/SMA inlet/outlet 等探针。 |
| `Plot_GX101R1_Probe_Timeseries_Individual.m` | 兼容 wrapper。 | 旧调用入口，内部转到 fixed probe 逻辑。 |

### 其他文件

| 文件 | 作用 | 配合方式 |
|---|---|---|
| `dependency_audit.txt` | 轻量依赖审计记录。 | 只作人工参考。 |
| `README_REMOTE_RUN.md` | 当前说明文件。 | 接手、远程部署、并行运行前先读。 |

## Fast 规则

当前 fast 不是固定步长，也不是 parpool。fast 依赖以下条件：

1. 使用 `accelerator` 模式。
2. 每个 MATLAB worker 在同一 session 内连续跑完整 cycle，不要每个 cycle 重启 MATLAB。
3. 每个 case 有独立 codegen cache，避免并行 cache 冲突。
4. 路径短，输出目录短。
5. 不强制 rebuild `.slx`。
6. 不固定 `InitialStep`，保持 `auto`。
7. 不收紧 `AbsTol`，保持 `1e-3`。
8. 不启用 SimState、daessc、Rapid Accelerator。

第一次启动或第一个 cycle 可能慢，因为 MATLAB/Simscape/accelerator/cache 需要初始化。长循环中如果某个 stage 突然很慢，优先检查：

- 是否有 min-step warning
- 是否某个 case 独立 cache 被污染
- 是否该 stage 的 flush 明显过冲/欠冲
- 是否 MATLAB 进程变成单核长时间求解
- 是否输出文件长时间不更新

## 故障处理

常见问题：

1. PowerShell 禁止运行脚本。

   使用：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<script.ps1>"
   ```

2. `matlab` 找不到。

   把 MATLAB 加入 PATH，或用完整 `matlab.exe` 路径。

3. case 很快退出。

   查：

   ```text
   logs\powershell_stderr.log
   matlab_error.txt
   runner_error.txt
   matlab_diary.txt
   ```

4. 某个 case 几小时没有结束。

   先看该 case 最新文件更新时间和 MATLAB CPU。若还在写 checkpoint 或 CPU 有计算，不要杀。若完全无更新且 stderr/error 存在，再停止该 case。

5. 误启动重复 case。

   用 PowerShell 按输出目录关键字查进程 CommandLine，再精准杀对应 PID，不要按任务管理器盲杀所有 MATLAB。

## 不要做的事

- 不要把完整 gx101r1 历史工作区复制到每个工况。
- 不要把所有 case 放进同一个 pref/tmp/codegen cache。
- 不要手动打开 `.slx` 后保存再长跑。
- 不要修改 `Output` 内生成的 `run_case.m` 当作主线代码。
- 不要把 validation failed 等同于 runner failed；长循环初筛主要看 `summary.json`、`stages.csv`、温度趋势、flush、min-step、compensation/reused。
- 不要把 `COP_no_pump` 当成真实系统 COP；工程 COP 需要加入泵/电机/驱动功。

## 接手建议

新负责人接手时，按顺序做：

1. 复制本文件夹到短路径，例如 `E:\gx101r1_R69_remote`。
2. 跑 MATLAB license 检查。
3. 跑一个 1-cycle smoke：

   ```powershell
   $repo = "E:\gx101r1_R69_remote"
   powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\Launch_OneCase.ps1" `
     -RepoRoot $repo -RunId smoke_v050_t040_1c -VStar 0.5 -StageTime 0.4 -NCycles 1
   ```

4. 查看 `Output\smoke_v050_t040_1c\v050_t040_1c\summary.json` 和 `stages.csv`。
5. 确认 smoke 没有 `runner_error`、`compensation`、`reused`、`min_step_warning`。
6. 再启动并行长循环。

这份轻量包是当前分支大改的基准。后续结构、PI、泵功、COP 或大规模扫参改动，都应先从这里分支，保留当前包作为可复现 baseline。

# SMA-SE 第二十九阶段：几何管路与瞬时换阀守恒审核

日期：2026-09-07。本阶段取得组件级通过证据，完整主目标未完成。C200 主线、生产本构/温度/相分数/buffer/PI 状态均未修改。

## 1. 结果及适用范围

本轮完成两组真实原生/守恒几何管配对实验，共 24 个工况，每例至 1 s，MATLAB 自然退出 0。两组分别采用 10 ms 阀动作和原瞬时换阀，各六个守恒管工况均通过原质量 `1e-15 kg`、能量 `1e-8 J` 门禁，包括全部局部账本、独立物性表重建和外部总账，而非只检查内部端口相加。

瞬时换阀组最大守恒库存残差为 `8.7244394e-18 kg`、`3.6379788e-12 J`。此结果不依赖新增 10 ms 平滑。它也不表示原生产恒容腔版本已经通过，更不代表完成整机周期、外部热流、Table 4 成对端点或完整状态恢复。

## 2. 为什么改管路模型

实际检查 `Integrate_HeatDriveECC_Constitutive21_Interface.m` 的 `configure_sma_valve_manifolds` 和 `ensure_sma_pump_manifold_volume`：泵前、泵后两个公共段使用 Constant Volume Chamber (TL)，其体积必须等于一段 `A*L`，L=0.2 m、内径 3.2 mm。这两个块保留流体质量和热库存，但直接将各自端口压力等同于内部压力，不代表沿程压降。

原网络两内部压力由理想压差源直接约束，前阶段已观察到 TP 坐标 BE 与端点库存 BE 的不一致。本轮检验物理几何管表示是否可以在保持同体积的同时解除这类刚性内部压力约束。

新守恒管使用项目原型的 `M=V*rho(T,p)`、`U=M*u(T,p)`、`der(M)=sum(mdot)` 和 `der(U)=sum(Phi)+Q_H`。动量关系改为端口至中心的半管压降，使用已安装 MathWorks `foundation.thermal_liquid.elements.pipe_friction` 函数。两端对流仍使用原生 `port_convection`，特征长度与原生 Pipe (TL) 配对为 L/2。

**必须披露：相对旧恒容腔，对照不仅改变沿程阻力，也改变端口对流特征长度，从约 3.2 mm 改为 0.1 m。** 因此目前证明的是几何管组合表示的效果，不是已完成单一阻力因素的严格消融。未启用惯性，也未新增体积、顺应性或壁面热容。

## 3. 实验合同与运行记录

两管各 `1.6084954386379741e-6 m³`，面积 `8.04247719318987e-6 m²`，初始 340 K、2.5 MPa。仍用四独立无限供回液储库，热380/冷300 K、2.5 MPa；泵压差在 0.01 s 从0跳至260 Pa。每组原生/守恒、none/isentropic 泵功、1/0.5/0.25 ms 局部 BE 与同档全局 ode3，共十二例。

Solver Configuration 保持上一阶段严格组：DerivativeReplacement，残差和本地一致性绝对/相对容差均 `1e-12`。这不是物理库存容差。管路明确采用长度0.2 m、内径3.2 mm、附加等效长度0、粗糙度15 µm、层流/湍流阈值2000/4000、形状因子64。**粗糙度和转捩参数是显式库默认值，不是本轮找到的 Qian 实测数据。** 两管 H 端绝热，所有实际参数写入每例 metadata。

公共输出前缀：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/`。

| 目录 | 执行提交 | 记录 |
|---|---|---|
| `dual_pipe_friction_20260907` | `ca9d851` | 仿真前 checkcode 的 AGROW 退出1，未计算工况；原日志和诊断保留 |
| `dual_pipe_friction_20260907_v2` | `d9c689797498949f96b0a536cac0fa5dba54456e` | 固定记录字段列表，checkcode无警告；10 ms动作十二例完成至1 s，退出0 |
| `dual_pipe_hard_switch_20260907` | `7bbd60bf79e125664476f9a4d248e9de64b2cadc` | 保持几何/物性/求解配置，仅恢复0.5 s瞬时换阀；十二例完成至1 s，退出0 |

两次真实实验各含1092条标量时间序列。每例都是独立诊断初值，不加载或复位生产 OP。每个真实 MATLAB 前台只启动一次，等待同一 session 自然结束，没有定时器、heartbeat 或健康程序中止。

## 4. 严格门禁

| 项目 | 10 ms 几何管 | 瞬时换阀几何管 |
|---|---:|---:|
| 完整工况 | 12/12 | 12/12 |
| 守恒管库存通过 | 6/6 | 6/6 |
| 守恒最大质量残差 kg | 9.1886134e-18 | 8.7244394e-18 |
| 守恒最大能量残差 J | 3.6379788e-12 | 3.6379788e-12 |
| 全部空间端口恒等式 | 通过 | 通过 |
| 全部泵模式、实际阀命令、热激励 | 通过 | 通过 |
| 半管压降、连接压力一致性 | 通过 | 通过 |

所有区间和切换样本保留；未从库存残差扣除任何坐标修正项。审核根据实际管端口压力而非内部压力计算泵压差与泵功，防止沿用恒容腔的错误采样边界。

原生管对照仍未通过端点库存门禁：瞬时组最大约 `1.4696265e-7 kg`、`0.048137218 J`。原生管与守恒管采用同几何、阻力和端口对流长度，故不能把两者都称为通过。瞬时组所有阀口最低约300 K；非零泵功最高约 `0.744231 mW`，none模式仍为0。

守恒 none、1 ms 工况，热/冷有效路线均值约 `2.64049/2.78900 g/s`，半管最大压降约71.36 Pa。对照上一阶段无阻力腔的热流量约8.43 g/s，变化显著；不能将这项模型替换当成只改数值误差、无需重新审核流量与性能。

## 5. 修改文件与验证覆盖

以下文件位于 `C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/verification/`：

- `simscape_inventory_pipe/+ecc_inventory/conservative_chamber.ssc`：独立几何管组件目录，旧守恒腔源码不变，避免污染历史组件合同。
- `Audit_HeatDriveECC_DualChamberSwitch.m`：显式第八参数 `pipe_model`；实际参数和端口/压降记录；旧默认调用路径保留。
- `Audit_HeatDriveECC_DualChamberSwitchResult.py`：显式管模式和瞬时命令审核；泵边界移至正确端口；旧模式不接受未声明的新字段。
- `Audit_HeatDriveECC_DualPipeResult.py`：固定执行提交、输入哈希、逐例配对、参数/物理域、原库存及压降审核。
- `test_dual_pipe.py`：压降篡改、错误泵端口、瞬时/缓变命令混淆、物性域和伪造能量数据检出。
- `Plot_HeatDriveECC_DualPipe.py` 与 `Audit_HeatDriveECC_DualPipePackage.ps1`：新图及结果包审核。

130项 Python 回归测试通过。首次 AGROW 修复仅把循环内字段追加改成固定列表，没有屏蔽警告或改物理参数。所有后续 MATLAB checkcode 无警告、模型编译更新成功。

## 6. Fig17 给负责人的逐图说明

[Fig17 PNG](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_pipe_hard_switch_20260907/Fig17_geometric_pipe_inventory.png)；[矢量PDF](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_pipe_hard_switch_20260907/Fig17_geometric_pipe_inventory.pdf)。

- (a) 守恒管、none、1 ms 的实际管内及 V3 出口温度。0.5 s后入口管降温，出口管滞后；关闭支路的端口温度并不等于出口管内温度。初始化和切换代数跳变保留，不能把阀口曲线当成冷端输出性能。
- (b) 热/冷路线在0.5 s瞬时切换；流量降低来自当前几何管诊断，260 Pa命令没有为追求通过而增大。图中没有把关闭阀的近零泄漏画成完全无流，原始数值在MAT与审核表。
- (c) 全时刻质量库存误差，对比原生硬切换、守恒硬切换、守恒10 ms；原质量门禁明确保留。
- (d) 相同对照的能量库存误差。守恒结果达浮点/求解误差量级，不能在该区间宣称步长越小误差必然单调；原生管未通过。

已目视检查2640×1920 PNG，无图例遮挡，温度、流量、质量和能量分面板，不混用单位。本图是组件数值审核图，不是最终SCI整机性能图，也未完成外部期刊质量认证。

## 7. 结果包、哈希、存储与复核命令

新发布目录：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_pipe_release_20260907`。保存原始24例、日志、组件、合同、图和审核；首次未执行仿真的失败记录也保留。没有复制生产大MAT，没有删除冻结恢复点或旧失败科学证据。全工作区字节、本阶段新增证据和Git对象大小由包内 `workspace_storage_snapshot.json` 实测；本轮删除量0，不能冒称释放此前累计空间。

完整代码：Stage17 `tl_inventory_release_20260906/source_snapshot.zip` 加本包 `source_delta.patch`，直接相对Stage17基线，不叠加历史补丁。ZIP SHA-256仍为 `CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F`。最终提交在 `release.json`，逐项大小/哈希见 `result_manifest.csv`。

两项结果审核SHA-256：

- `pipe_friction_audit_v1.json`：`C3CD9E6FF6154027BC267ED0FA2BDDA8A344A0FBB88707E4210674C29F35649C`。
- `pipe_hard_audit_v1.json`：`925475445B874BCF3522E37BDB458177A69C4AEA5B2D30CF664EA477F86A80DE`。

```powershell
$r = 'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'
python -m unittest discover -s "$r/verification" -p 'test_*.py'
& "$r/verification/Audit_HeatDriveECC_DualPipePackage.ps1"
$tag = [guid]::NewGuid().ToString('N')
python "$r/verification/Audit_HeatDriveECC_DualPipeResult.py" --repo $r --output "$env:TEMP/pipe_finite_$tag.json"
python "$r/verification/Audit_HeatDriveECC_DualPipeResult.py" --repo $r --hard --output "$env:TEMP/pipe_hard_$tag.json"
```

离线复核需要PowerShell7、Python/numpy/scipy/h5py；无需再运行MATLAB。预期组件库存 true、production_recovery_allowed false、whole_model_first_law_verified false。`hard_switch_failure_resolved=false` 指旧恒容腔/生产版本未改判，不是新几何管瞬时试验失败；应同时阅读 schema 和逐例门禁。

重做真实瞬时配对实验时，MATLAB R2025b和Simulink/Simscape Fluids、干净源码树、全新输出目录，在repo中 `addpath('verification')` 后运行：

```matlab
Audit_HeatDriveECC_DualChamberSwitch( ...
    'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/dual_pipe_user_review/trial', ...
    'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181/segment_physical.mat', ...
    true, true, 0, 'DerivativeReplacement', 1e-12, true);
```

改第五参数为 `.01` 是有限动作对照。新实验记录新执行提交；不得覆盖冻结目录或编辑旧哈希来绕过固定历史合同审核。

## 8. 文献定位与下一步

Qian 2019：`C:/Users/86182/Desktop/冷凝文献/弹热制冷文献/A heat driven elastocaloric cooling system..pdf`，DOI `10.1016/j.energy.2019.06.094`，PDF3–6页，Fig.1、Table2、Eq.9/10。本轮沿用已核实的连接管0.2m、3.2mm几何，尚未证明两公共段和全模型所有已有连接管无重复计长，也没有新增Table4性能点。

Qian 2015：同目录 `（3）Thermodynamics cycle analysis and numerical modeling of thermoelastic cooling systems.pdf`，DOI `10.1016/j.ijrefrig.2015.04.001`，PDF7–9页，Fig.6、Eq.28–30。文献有限水箱/管壁热容和瞬时阀假设不能被本台架的四无限储库、绝热公共管替代。本轮没有改变文献COP边界或重新阅读更多未列出的文章。

原生管的沿程阻力、压缩性和可选惯性定义见 [MathWorks Pipe (TL)](https://www.mathworks.com/help/simscape/ref/pipetl.html)。本轮直接调用已安装的摩擦和端口对流函数；尚未进行摩擦本身的实验验证，库定义不是文献实测依据。

下一步按以下顺序进入主线，而不是因本组件通过就运行无保护outer solve：

1. 审核生产每条活动路线的连接管长度、体积、壁热容及阻力归属，排除公共段重复计长；对阻力和端口对流特征长度做必要独立消融。
2. 为经审定的几何管替换建立显式诊断模型开关和完整状态兼容合同；保留旧构建器与C200。结构变化不得直接加载旧OP或复位生产状态。
3. 在全系统观察窗口内重做全部流量/相变/外部热流/质量与能量库存门禁，再完成所有内部状态的周期稳态。成功的短管台架不能覆盖管壁、水箱、SMA/SE和buffer。
4. 仅在合法周期基线成立后进行固定Tc求解、正交敏感性和共同参数/共同周期窗口的zero-load与zero-lift成对端点；最后才完成热驱动COP/SCP/回热/工作图与SCI主图。

当前完整目标仍 active。使用 simulated/component diagnostic passed，不能使用完整系统 validated/reproduced。

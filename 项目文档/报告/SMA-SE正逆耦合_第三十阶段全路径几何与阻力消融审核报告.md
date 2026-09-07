# SMA-SE 第三十阶段：全路径几何与阻力消融审核

日期：2026-09-07。完整目标未完成，C200 冻结参考及生产状态不变。本轮完成整机几何导出及18个新增真实消融工况，不是生产长循环复现。

## 1. 新证据与结论

1. 从当前构建器实际构建、update 后导出115个几何/热质量对象和完整TL连接图，未加载任何OP、未运行或保存生产仿真。
2. SMA阶段1/3的主活动路线各有21段床内管、1段相应换热器管及两个公共恒容腔。公共腔体积相当于两段0.2m连接管，但实际没有沿程压降。泵压差前馈不是耗散元件，不能以“前馈含附件损失”证明实际公共段已建模阻力。
3. 新增三个消融组合，各六例完成至1s。无阻力时，无论端口对流长度3.2mm还是100mm，库存误差均约0.1395J；有阻力、短长度通过原门禁。结合前阶段有阻力、长长度对照，可区分阻力和对流长度的作用。
4. 严格容差下无阻力、短长度的瞬时换阀也能完成，因此不能继续将旧温度断言消失归因于长对流长度或有限阀动作。完成计算、端口一致和端点库存闭合仍是不同门禁。

## 2. 实际路线与库存

数据：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/production_route_geometry_20260907/model/route_geometry.json`。执行提交 `61e880928584bc3308f6df459b81dbebd52aadb4`，MATLAB检查和模型update通过，程序自然退出0。只读取C181的冻结options，源MAT SHA-256为 `6E5D15B2C2F67799748187F1BD15E0CBA1B08C7BCF1A5C1D1639B35AFE6CCC13`。

Python根据物理连线及层级连接合并节点，去除泵内部连接，再移除非当前阶段的SMA阀支路，要求泵A至B的外部主路线唯一。该次序是图遍历方向，不据此声称瞬态流向。关闭阀的实际泄漏非零，此图仅用于主活动路线计数，未代替泄漏仿真。两个真实TL物性域的归属也进行了拓扑校验。

| 主路线 | 活动阀 | 床内管 | 换热器管 | 公共腔 |
|---|---|---|---|---|
| SMA阶段1 | V1/V3/V5 | HoldPipe_001..021 | SHEX/HotPipe | 泵前、泵后各一 |
| SMA阶段3 | V2/V4/V6 | CooldownPipe_001..021 | HHEX/SMAHotPipe | 同两个公共腔 |

每条路线实际22段Pipe块长度之和约 `0.9672207665 m`，流体几何体积之和 `1.8231681927e-5 m³`。这些是模型的水力管长参数，不能当成文献所有实体连管的测量长度；床的等效几何与连接管必须分开。22段的额外等效阻力长度参数均为0。

公共腔另含体积 `3.2169908773e-6 m³`，对应0.4m、3.2mm连接管库存，其水力阻力长度为0。拓扑上没有另一对同位置、同几何的0.2m管与它们串联。因此若将公共腔“替换”为等体积阻力管，不会在这两个块处额外增加体积；但若在公共腔之外“追加”两段管，则会重复库存。该判断不是说已证明与文献Fig.1所有管段的一一映射。

原说明位于 `Build_HeatDriveECC_EighthRound_Defaults.m` 的 `connecting_pipe_implementation_note`，称既有路线前馈保留附件水力损失。实际前馈来自识别的压差/流量工作点，是控制驱动量，不是TL能量/动量边界上的耗散对象。本轮没有直接改写该冻结说明或生产控制器；此处明确记录它不能作为“无需物理管阻”的充分依据。

## 3. 管壁热容仍需明确

115个对象包括67段Pipe、2个恒容腔和46个Thermal Mass。后者按实际块身份分为42个SMA/SE固体节点和4个冷热源/负荷质量块；没有未分类块，也没有显式连接管命名的热质量块。完整热域连接图尚未导出，所以不能据此排除已有源/汇等效热容中含有补偿量，不能直接把缺口加到任意节点。

本轮重读Qian2019本地PDF第3–6页并渲染查看第4页Fig.1。第6页Table2及脚注明确连接管内径3.2mm、长度0.2m、壁厚0.5mm、体积热容1.8 J/(K·cm³)。若假设恰好两根这样的实体管壳，其总热容为：

```text
C_wall = 2 * pi/4 * [(0.0032+2*0.0005)^2 - 0.0032^2] * 0.2 * 1.8e6
       = 4.1846014146 J/K
```

这是明确假设下的几何换算，不是已确认应向当前模型添加的数值。文献Fig.1是示意图，不足以唯一确定本模型两个泵侧公共腔对应的全部连接管数量和位置；第5页还说明附件热质量估计可能需要修正系数。完整映射与已有热容补偿的来源审核仍未完成。

文献：`C:/Users/86182/Desktop/冷凝文献/弹热制冷文献/A heat driven elastocaloric cooling system..pdf`，DOI `10.1016/j.energy.2019.06.094`，PDF第4页Fig.1、第5页Section3.1及Eq.9/10、第6页Table2/脚注。第一次文本打印因Windows编码失败，改用Python UTF-8后读取成功，未修改PDF。第4页渲染图保存在本轮几何证据目录，便于负责人对照。

附件方程追溯仍指向Qian2015：同文件夹 `（3）Thermodynamics cycle analysis and numerical modeling of thermoelastic cooling systems.pdf`，DOI `10.1016/j.ijrefrig.2015.04.001`，PDF7–9页、Fig.6及Eq.28–30。此次主要重新检查的是2019文献，不宣称重新读完全部Qian文章。

## 4. 独立消融及真实执行

保持两腔体积、四独立储库、340K/2.5MPa配对初值、380/300K边界、260Pa泵命令、0.5s瞬时换阀及严格求解容差。每个组合包括none/isentropic泵功与1/0.5/0.25ms三档局部BE，同档全局ode3，共六例，未加载生产OP。

新组件单独位于 `verification/simscape_inventory_ablation/+ecc_inventory/conservative_chamber.ssc`，旧管组件源码不变。参数只允许摩擦系数乘子0或1及显式端口对流特征长度；不加入小阻力、epsilon或隐式数值泄漏。当前试验管壁H端绝热，尚未纳入上述待核实管壳热容。

| 组合 | 来源/执行提交 | 完成 | 原库存门禁 | 最大质量kg / 能量J |
|---|---|---:|---|---|
| 无阻力，100mm | 本轮 `b76c95549f12894acbfdf392e997d9482dca0179` | 6/6 | 失败 | 1.2572314e-7 / 0.139492568 |
| 有阻力，3.2mm | 本轮同提交 | 6/6 | 通过 | 8.4940464e-18 / 6.0893512e-12 |
| 无阻力，3.2mm | 本轮 `e0b6eea619b4bd0e1e7c520c0e1e85a9f54deab4` | 6/6 | 失败 | 1.2572313e-7 / 0.139492564 |
| 有阻力，100mm | 沿用第二十九阶段已冻结六个守恒对照 | 6/6 | 通过 | 8.7244394e-18 / 3.6379788e-12 |

本轮新增18例，最后一行不是本轮新增。既有对照使用独立几何管组件，其端口特征长度L/2=0.1m，摩擦函数相同；不是声称四组都由同一个编译文件产生。粗糙度仍为显式库默认15µm，不是Qian实测值。

三组新实验MATLAB均自然退出0，每组558条标量序列。全部端口恒等式、显式阻力状态、热激励和阀命令通过，最低阀口温度约300K，但两组无阻力库存仍失败。原质量 `1e-15 kg`、能量 `1e-8 J` 门禁不变，未删除切换区间或扣除诊断差额。

本轮结果将下一步重点指向保留有限阻力并处理完整热/状态边界。对流长度在已测范围内不是库存闭合通过的必要条件；仅凭它变化不能解释原断言。原第二十七阶段默认容差硬切换失败保留，不被后续严格容差试验改判。

## 5. 图、代码和测试

[Fig18 PNG](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/production_route_geometry_20260907/Fig18_pipe_friction_ablation.png)；[PDF](C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/production_route_geometry_20260907/Fig18_pipe_friction_ablation.pdf)。

(a)质量、(b)能量分轴展示每个组合六例、全部时刻和账本的最大残差。横轴仅为两个实测特征长度，连线用于分组，不是对未测参数的预测。蓝线为有限阻力，红线为无阻力，空圈标记沿用的上阶段对照，门禁虚线未调整。已目视查看2400×1200 PNG，图例与数据不遮挡；这是数值诊断图，非完整SMA-SE性能图或最终SCI主图。

新增 `Audit_HeatDriveECC_RouteGeometry.m`、`Audit_HeatDriveECC_RouteGeometryResult.py`、`Audit_HeatDriveECC_PipeAblation.py`、`Plot_HeatDriveECC_PipeAblation.py`、`Audit_HeatDriveECC_RouteAblationPackage.ps1`、`test_route_geometry.py` 和独立消融SSC。原台架第九参数支持显式消融，旧默认不变。

135项回归测试通过，新增主路径缺失、并联歧义、泵短接、单位/负几何及消融轴注册测试。几何结果v2将初稿的汇总字段改为可逐项核查的热质量分类与名单；原v1小摘要保留，实际模型无需重跑。

## 6. 结果包和验证命令

结果包：`C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/route_ablation_release_20260907`。包含本轮18例、模型几何、日志、图、父阶段引用、逐文件哈希、测试日志和独立复算回执。本轮没有复制生产大MAT、没有删除冻结参考或旧失败原始证据。完整字节/Git对象审计见 `workspace_storage_snapshot.json`，新增数据以MB计，不将包完整性等同于科学门禁。

完整源码仍使用Stage17 `tl_inventory_release_20260906/source_snapshot.zip` 加本包相对Stage17的直接 `source_delta.patch`，不叠加历史补丁。最终提交在 `release.json`，文件哈希在 `result_manifest.csv`。基线ZIP SHA-256为 `CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F`。

```powershell
$r = 'C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote'
python -m unittest discover -s "$r/verification" -p 'test_*.py'
& "$r/verification/Audit_HeatDriveECC_RouteAblationPackage.ps1"
$tag = [guid]::NewGuid().ToString('N')
python "$r/verification/Audit_HeatDriveECC_RouteGeometryResult.py" --repo $r --output "$env:TEMP/geometry_$tag.json"
foreach ($m in @('no_friction_long_port','friction_short_port','no_friction_short_port')) {
    python "$r/verification/Audit_HeatDriveECC_PipeAblation.py" --repo $r --mode $m --output "$env:TEMP/${m}_$tag.json"
}
```

需要PowerShell7、Python/numpy/scipy/h5py；离线命令不运行MATLAB。预期新增18例中6例库存通过、12例失败，production_recovery_allowed始终false。真实重跑使用上一阶段八参数调用后追加第九参数上述模式名，并保持第五参数0；必须全新目录和干净代码树，记录新的执行提交，不能覆盖或伪造历史合同。

## 7. 下一步完整主线

本轮完成主活动路线计长和阻力/对流长度消融，但仍缺完整热域归属与文献连接管映射。下一步先导出公共连接管H端、已有源汇热容与SMA/SE固体热连接，明确壁热容是否已被等效吸收；再建立诊断替换开关及完整状态映射合同，防止重复库存、重复壁热容和非法旧OP恢复。

生产集成之后，仍必须通过所有流量、相变、全控制体质量/能量、热流/泵功以及完整内部状态周期门禁，才能进入受保护固定Tc求解、正交敏感性与共同参数/共同窗口的成对Table4端点。C200保持唯一冻结主线参考，不把新组件实验当作生产恢复点。主目标 active，尚未完成整机复现和最终图集。

# Agent5 最小保留只读审计

本轮只读，不删除、不移动、不修改数据。

| 组 | raw 总量 | 建议保留代表性 raw | compact 替代候选 | 预计候选释放 |
|---|---:|---|---|---:|
| v64c1 | 1.273 GiB | C110, C118 | C116 | 0.424 GiB |
| v65c1 | 2.971 GiB | C110, C126 | C116, C118, C120, C122, C124 | 2.122 GiB |
| v66_sensitivity_nominal_20261017 | 2.548 GiB | C020 | fresh_native_probe, C002, C012, C014, C016, C018 | 2.127 GiB |
| v68r2 | 2.547 GiB | C020 | fresh_native_probe, C002, C012, C014, C016, C018 | 2.126 GiB |
| v70case2 | 2.548 GiB | C020 | fresh_native_probe, C002, C012, C014, C016, C018 | 2.127 GiB |
| v71case3 | 4.263 GiB | C020 | fresh_native_probe, C002, C004, C006, C008, C010, C012, C014, C016, C018 | 3.842 GiB |

## 统一保留对象

所有组必须保留代码、模型、参数、Git/线程归属、case/phase closeout、collection result、failure marker、packet manifest、cycle summary、temperature probes、mechanism/boundary/contract 文件及 storage/retirement receipt。

## 争议与限制

- v64/v65：compact 证据完整，但是否保留 C124 等最后稳定窗口需要在执行删除前单独确认。
- v66/v68/v70/v71：storage receipt 仍把 raw 标为 same-case dependency；本审计按最小保留原则提出候选，但没有执行删除。
- 未发现 `.h5`/`.hdf5`，不存在需要处理的 HDF5 external link。

## 路径

- JSON: 
C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_minimal_retention_audit\minimal_retention_audit.json
- CSV: 
C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_minimal_retention_audit\minimal_retention_raw_inventory.csv

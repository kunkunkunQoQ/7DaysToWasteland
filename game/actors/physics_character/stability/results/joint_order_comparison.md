# 关节登记顺序对照

[CSV](joint_order_comparison.csv) 收录 GodotPhysics3D 4.6.3 的 70 组全身观测。各组均使用 `palms_rolling`、60 Hz、5 秒、300 个固定步。五种顺序各运行两遍，每种顺序的全身、逐关节和撞击事件三份汇总 CSV 在两遍之间逐字节一致。表中每组保留一次。

| 登记顺序 | 通过工况 | 最大锚点分离 |
|---|---:|---:|
| `original`、`paired_bfs` | 各 4/14 | 19.55 cm，左侧撞击时的右踝 |
| `distal_bfs`、`reverse_original` | 各 4/14 | 50.18 cm，手臂撞击时的左肘 |
| `legs_first_bfs` | 4/14 | 32.87 cm，正面撞击时的右腕 |

在独立项目副本中，保持刚体创建顺序、锚点、物理参数和地面一致。仅调整 `body/physics_rig.gd` 中创建原生关节的循环，先将 `config.build_joints()` 的行按 `child` 索引，再依次取行交给原有建关节代码。下列 `LR` 表示该段先左后右，如 `thigh_l thigh_r`。

- `original` 使用配置的原始行序。`reverse_original` 将这 15 行整体逆序。
- `paired_bfs` 按 `spine, thigh LR, chest, calf LR, head, upper_arm LR, foot LR, lower_arm LR, hand LR` 登记。`distal_bfs` 将这 15 个实际名称整体逆序。
- `legs_first_bfs` 按 `thigh LR, spine, calf LR, chest, foot LR, upper_arm LR, head, lower_arm LR, hand LR` 登记。

每种副本分别运行两次 `run_matrix.py --godot <引擎路径> --project <副本路径> --out <独立输出目录> --profiles palms_rolling --hz 60`。对比两次的 `matrix_body.csv`、`matrix_joints.csv`、`matrix_impacts.csv`。本表只收录使用修正启动顺序的 60 Hz 数据。

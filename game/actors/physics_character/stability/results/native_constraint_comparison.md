# 原生约束单变量对照

固定 `palms_rolling` 人体、GodotPhysics3D 4.6.3、60 Hz、16 次空间迭代，每种配置独立运行同一套 14 个工况，各观察 5 s。共 154 次。每次只更改表中的一项。记录每个工况完整的全身误差、穿透、恢复、反向运动和刚体命中指标，并附启动后从物理服务器读回的五个值。[全部 154 行 CSV](native_constraint_comparison.csv)

| 更改项 | 有效值 | 通过 / 14 | 全矩阵最大锚点分离 cm | 存在末窗往复的工况 | 未证实完全恢复的工况 | 穿透失败工况 |
|---|---:|---:|---:|---:|---:|---:|
| 原始对照 | — | 4 | 19.55 | 2 | 6 | 10 |
| 多轴平移 softness | 0.45 | 3 | 15.74 | 7 | 5 | 9 |
| 同上 | 0.90 | 5 | 22.93 | 7 | 6 | 8 |
| 多轴平移 damping | 0.70 | 4 | 38.41 | 6 | 6 | 9 |
| 同上 | 1.25 | 4 | 13.09 | 5 | 2 | 10 |
| 多轴平移 restitution | 0.25 | 4 | 21.80 | 4 | 7 | 9 |
| 同上 | 0.75 | 5 | 122.01 | 3 | 5 | 9 |
| 膝肘铰链 bias | 0.15 | 5 | 13.24 | 6 | 6 | 9 |
| 同上 | 0.50 | 5 | 17.61 | 4 | 6 | 8 |
| 独立空间 contact bias | 0.40 | 4 | 19.55 | 2 | 6 | 10 |
| 同上 | 0.95 | 4 | 19.55 | 2 | 6 | 10 |

**参数施加位置。** 在测试人体建好后，对 11 个 `Generic6DOFJoint3D` 的三个轴调用 `PhysicsServer3D.generic_6dof_joint_set_param`，一次选取 `G6DOF_JOINT_LINEAR_LIMIT_SOFTNESS`、`G6DOF_JOINT_LINEAR_DAMPING` 或 `G6DOF_JOINT_LINEAR_RESTITUTION` 中的一项。原始有效值依次为 0.7、1.0、0.5。平移解算器用 softness 缩放总冲量，用 damping 缩放轴向相对速度项，用 restitution 缩放锚点偏差除以步长的回正项。铰链组只设置四个膝肘的 `HINGE_JOINT_BIAS`，原值 0.3。空间组只设置私有空间的 `SPACE_PARAM_CONTACT_DEFAULT_BIAS`，原值 0.8。[平移解算公式](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/godot_physics_3d/joints/godot_generic_6dof_joint_3d.cpp#L157-L212)

**异常与归因。** restitution 从 0.5 增至 0.75 时，右侧撞击 `hit_right` 的第 33 步，右前臂—右手腕 `hand_r` 的锚点分离达到 **1.2201 m**。同组总通过数仍上升一项，最坏事件明确恶化。damping 1.25 将最坏锚点分离降至 13.09 cm，末窗往复却增至五个工况。空间 contact bias 两档均成功读回设值，但各工况与对照的物理结果一致。该版本的原生刚体接触分支从常量 0.8 开始，仅在形状定义了自订 bias 时覆盖；软体接触分支会读取空间值。上述参数均未作为通过阶段 2 的配置发布。[刚体对接触 bias](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/godot_physics_3d/godot_body_pair_3d.cpp#L337-L354) · [软体接触分支](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/godot_physics_3d/godot_body_pair_3d.cpp#L730-L748)

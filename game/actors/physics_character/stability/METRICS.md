# 被动人体关节遥测

测量器只读人体数据，使用 GodotPhysics3D 4.6.3 解算完成后的姿态、速度与接触流形。每次 `sample` 接收场景自定义的物理步号。通过矩阵入口的 `--trace` 保留所选工况的逐步数据，每个样本对应十五行 CSV。一次受击的运动可能经过相邻肢体传播，报表同时保留峰值帧与前一帧的外部接触部位。

| 字段 | 定义 |
|---|---|
| `anchor_m` | 静息配置中的同一锚点分别变换到父、子刚体局部，随后用当前两个刚体姿态投回世界空间，取两点的欧氏距离。 |
| `angles_xyz_deg` | 设 A、B 为父子当前的世界关节基。多轴关节对 B⁻¹A 作 XYZ 欧拉分解，与该引擎的限位坐标顺序一致。铰链的有符号 Z 坐标取子 Y 轴投影至父 X/Y 平面的角度；X、Y 坐标填零，另以 `hinge_axis_error_deg` 记录两侧设计 Z 轴夹角。 |
| `angular_error_deg` | 将上述关节坐标夹到配置区间，重建一个允许的取向，计算当前取向到这个取向的最短四元数旋转角。允许范围内的自由屈伸误差为零。铰链同时计入偏轴弯曲。多轴欧拉限位的夹紧取向是可复现的参考取向，未作全局最近取向的优化。 |
| `limit_violation_deg` | 各受限旋转坐标越过其上下限的绝对角量，取三轴最大值。铰链另外记录偏轴角度。此处报告几何角度；引擎铰链内部使用 `atan2fast`，精确 `atan2` 与其近似的最大读数差约 4.08°。 |
| `omega_child_minus_parent_joint_frame_rad_s` | 世界角速度之差 ω子 − ω父，投影到父关节基 A 表达，单位 rad/s。这是相对角速度向量，欧拉角微分另有轴耦合。 |
| `peak_anchor_m`、`rms_anchor_m`、`residual_m` | 依次为全时段最大值、逐步 RMS、末 0.5 s 的 RMS。每个关节也有全时段角误差峰值与 RMS、末段角误差 RMS 和峰值限位越界。整人 RMS 对所有关节、所有步的误差平方取平均再开方。 |
| `peak_tick`、`peak_*_world_*`、`previous_*_world_*` | 峰值首次出现的物理步、峰值步与前一步两端刚体的世界线速度和角速度。发生在采样第一个物理步的峰值，前一步速度回填为首次观测；此时没有真实前序样本。 |
| 外部接触与 `*_impulse_Ns` | 排除同一人体的 16 个刚体后，记录每一端的外部对象名；冲量为该端各外部接触点冲量模长之和。流形中可能存在零冲量点。模拟内部求解子迭代的瞬间未对脚本公开。 |
| `recovery_s` | 从最后一次指定撞击步（自由下落取首次外部接触）到该关节最后一次回到 12 mm、6° 双容差内的耗时。要求此后至少保持 0.25 s，且直到采集结束没有再越界。值 0 表示受击起一直满足，−1 表示本观测窗未证实恢复或未发生接触。整人恢复要求十五个关节全部满足。 |
| `tail_anchor_span_m`、`tail_anchor_reversals` | 末 0.5 s 内锚点最大值减最小值，及越过 2 mm 回差后的反向次数。 |
| `tail_rel_omega_rad_s`、`tail_omega_reversals` | 同一末窗内相对角速度向量模长的 RMS，以及各局部轴越过 ±0.5 rad/s 后速度变号次数的最大值。 |

**整人约束判据。** 任一姿态或速度非有限、任一关节锚点达到 18 cm、末窗未证实全部关节恢复或仍存在显著往复时，该次的遥测验收失败。显著往复的筛查条件为末窗至少四次锚点反向且振幅范围超过 10 mm，或同轴角速度至少四次变号且相对角速度 RMS 超过 1 rad/s。测试场地的穿透、命中有效性由独立探针验收。此判据对给定强度、观测时长和姿态负责。

**自检。** 在项目根目录执行 `godot --headless --path . --script res://game/actors/physics_character/stability/verify_joint_telemetry.gd`。夹具覆盖允许的膝屈曲、反向越限、铰链偏轴、带符号多轴复合角、真实跌落的十五个关节和逐步 CSV 读回。

## 正面跌落的腕部往复

原始配置在正面跌落后出现双手腕小幅往复。在 60 Hz、8 s 工况的末 30 步，左右手掌和前臂在每一步都与地面接触。双腕相对角速度 RMS 为 1.314、1.223 rad/s，各自有 8 次同轴反向。手腕实际关节角在数度范围内反复改变，锚点跨度约 2 mm。延长到 18 s 后，RMS 为 1.467、1.576 rad/s，反向次数为 11、10。全身允许休眠后重跑 8 s 和 18 s，两组均有 0/16 段入睡，末窗读数逐项相同。120 Hz、8 s 时，左腕已近静止，右腕仍在半秒内反向 29 次。两腕采用多轴关节，判定取自实测刚体角速度与接触，铰链读角近似不会直接生成这组数值。结果与腕部角限位和持续接触之间的相互作用相符。[8 s、18 s 对照原始摘要](results/wrist_contact_chatter.csv)

复测时选择 `--case=drop_front --profile=baseline --hz=60 --duration-s=8 --trace`，将时长换为 18 s，分别添加或省略 `--allow-sleep`。在 4.6.3 读回同一多轴 X 关节的角限位力矩上限时，场景节点值为 0，服务器有效值为 300；角马达上限节点值为 300，服务器读回 0.1，马达关闭。原因可追到 GodotPhysics3D 设置角马达力矩时写入了角限位力矩字段，因此初始化后的服务器值与节点缓存不同。[多轴参数写入](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/godot_physics_3d/joints/godot_generic_6dof_joint_3d.cpp#L485-L506)

引擎版本依据见 [Generic6DOF 的相对基与 XYZ 分解](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/godot_physics_3d/joints/godot_generic_6dof_joint_3d.cpp#L232-L236)、[铰链读角](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/godot_physics_3d/joints/godot_hinge_joint_3d.cpp#L353-L359)及 [atan2fast 的近似](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/godot_physics_3d/godot_joint_3d.h#L59-L71)。

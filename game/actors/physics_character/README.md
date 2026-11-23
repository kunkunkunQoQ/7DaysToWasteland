# PhysicsCharacter 独立测试

主动人体使用同一套刚体、关节和状态接口。阶段 3 站立通过，阶段 4 行走受阻。当前源码的八案结果、回滚检查点和测试入口见[主动物理角色阶段记录](active_tests/PHASE_STATUS.md)。

阶段 2 的双频被动跌落、撞击、逐关节误差与实测耗时见[稳定性工程报告](stability/REPORT.md)。以下场景和命令保留阶段 1 基线。

阶段 1 提供能受重力、地面和外力影响的被动人体。初始直立只是出生姿态。放任人体倒下或用试块撞它，可以观察同一次物理运动如何传到状态接口、视觉骨骼和调试面板。

## 打开测试场景

用 Godot 4.6.3 打开项目，在编辑器中打开 [physics_character_test.tscn](tests/physics_character_test.tscn)，按 **F6** 运行。**空格**给橙色 12 kg 试块一次朝向人体的有限冲量，**R** 重新装载测试场景。青点表示重心，橙点表示双脚底中点。面板显示固定步频、步号、位置、速度、足底接触、支撑脚和跌倒状态。

也可在含 `project.godot` 的目录运行下列命令。`godot` 指本机 Godot 4.6.3 可执行文件。新检出项目可先在编辑器完成导入，或执行第一条命令。

```powershell
godot --headless --editor --path . --import
godot --path . res://game/actors/physics_character/tests/physics_character_test.tscn -- --physics-hz=60
godot --path . res://game/actors/physics_character/tests/physics_character_test.tscn -- --physics-hz=120
```

测试台继承项目的 GodotPhysics3D 与 18 m/s² 重力。省略频率参数时沿用进程当前频率。独立运行测试台时，参数只覆盖本进程的固定步频，离开场景后恢复进入时的值。实例化人体或把测试台作为其他场景的子节点均不会改变步频。

## 对外接口

实例化 [physics_character.tscn](physics_character.tscn)，在加入场景树前设置出生位置与朝向。节点完成 `_ready()` 后，游戏逻辑通过 `get_state() -> PhysicsCharacterState` 读取快照，或订阅 `state_updated(state)`。第 0 号快照描述出生姿态，步长为 0。随后每个固定物理步发布一次新快照，接触信息来自最近一次引擎解算。订阅者可以保留旧快照。身体节点和物理句柄仅供子系统内部及结构测试使用。

| 字段 | 含义 |
|---|---|
| `foot_position`、`left_sole_position`、`right_sole_position` | 双侧鞋底标记的中点及各自位置，离地后仍有值。脚点可与真正的地面接触点分别读取。 |
| `pelvis_position`、`eye_position` | 骨盆中心、随头部转动的双眼中点，单位 m。 |
| `center_of_mass`、`linear_velocity` | 所有肢体质量加权的重心和重心速度，单位 m、m/s。 |
| `angular_velocity` | 骨盆在世界坐标中的角速度，单位 rad/s。 |
| `grounded`、`support_feet` | 至少一只脚承重时接地为真。位掩码 0 无、1 左、2 右、3 双脚。检查外部接触的法线、足底朝向、鞋底位置和法向冲量。 |
| `body_grounded` | 任一肢体有向上的外部接触时为真。人体侧卧、双脚悬空时，身体接地和足底承重可分别观测。 |
| `left_support_points`、`right_support_points` | 当步的世界坐标接触点。读取方取得自己的数组副本。 |
| `fallen` | 躯干相对直立倾斜至少 60° 且有非足部向上的外部接触时进入跌倒状态；足底重新承重且倾角降至 45° 以内时退出。阈值可配置。 |
| `tick_index`、`step_seconds`、`body_poses` | 本实例的步号、步长和只读的各段世界变换。视觉、遥测只消费这些数值。 |

`submit_intent(velocity, facing, jump_pressed, grab_held)` 接收世界空间期望速度和独立面向。两次物理步之间的跳跃请求会保留到下一步，抓取保留按住状态。控制器的 `control_step(state, intent, delta)` 是后续平衡、步态和肌肉模块的接入点。当前此端口没有执行器。

## 文件与职责

| 模块 | 文件及职责 |
|---|---|
| 角色入口 | [physics_character.gd](physics_character.gd)、[physics_character.tscn](physics_character.tscn) 负责组装、固定步、状态发布和意图入口。 |
| 人体配置 | [config/physics_character_config.gd](config/physics_character_config.gd)、[config/default.tres](config/default.tres) 定义形状、静息位置、质量、关节拓扑、轴与限位、碰撞、接触和跌倒阈值。默认总质量 66.1 kg。 |
| 物理人体 | [body/physics_rig.gd](body/physics_rig.gd) 创建骨盆、脊柱、胸、头及双侧各三段手臂和腿，连接四个膝肘铰链及十一个多轴关节。相邻段免自碰撞。 [body/body_segment.gd](body/body_segment.gd) 从引擎解算结果收集真实接触。 |
| 状态 | [state/state_sampler.gd](state/state_sampler.gd) 汇总刚体反馈。 [state/physics_character_state.gd](state/physics_character_state.gd) 定义面向消费者的只读值接口。 |
| 控制器 | [controllers/intent_controller.gd](controllers/intent_controller.gd)、[controllers/physics_character_intent.gd](controllers/physics_character_intent.gd) 锁存并按固定步分发意图。 |
| 显示 | [visual/physics_character_visual.gd](visual/physics_character_visual.gd) 建立 16 骨视觉骨架，按父骨局部空间同步灰盒。 [debug/telemetry.gd](debug/telemetry.gd)、[debug/telemetry.tscn](debug/telemetry.tscn) 显示数值和标记。两者均直接读取状态快照。 |
| 测试 | [tests/physics_character_test.tscn](tests/physics_character_test.tscn)、[tests/test_arena.gd](tests/test_arena.gd) 提供平地、试块、相机和运行参数；[tests/verify_phase1.gd](tests/verify_phase1.gd) 执行自动验证。本说明和对应脚本的 Godot UID 文件同在子系统目录内。 |

## 自动验证

```powershell
godot --headless --path . --script res://game/actors/physics_character/tests/verify_phase1.gd -- --physics-hz=60
godot --headless --path . --script res://game/actors/physics_character/tests/verify_phase1.gd -- --physics-hz=120
```

每次执行产生一行 `OBS` 测量数据及一行 `PHASE1 passed=… failed=…`。断言失败时进程退出码为 1。套件在实际固定帧中推进 4 秒，除测试台人体外，还会临时生成一具无视觉、从 3 m 高处侧倾释放的人体。覆盖关节连接、刚体与重力、实际撞击及足底接触、跌倒检测、历史快照、意图边沿、全骨骼同步及离场步频恢复。

Godot 4.6.3 官方 Windows 版本、GodotPhysics3D 的交付基线如下。锚点误差是两端的局部锚点分别转换到世界坐标后的距离，取两个测试人体、所有关节和四秒窗口内的最大值。

| 固定频率 | 观测步数 | 最大锚点分离 | 断言 |
|---|---:|---:|---:|
| 60 Hz | 240 | 0.1093 m | 21/21 |
| 120 Hz | 480 | 0.0639 m | 21/21 |

18 cm 是这组初始化测试用来捕捉结构发散的宽松上限。阶段 2 需要记录各关节的峰值与残余误差、越限和碰撞穿透，在不同跌落姿态、推力方向及重复撞击下再定容许误差。主动站立、迈步、动态平衡、跳跃、起身和抓取均留待后续阶段。两档运行结果没有用于决定正式游戏的物理频率。

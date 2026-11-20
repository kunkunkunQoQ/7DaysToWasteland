# 单变量试验

重力为 18 m/s²。原始基线是阶段 1 的人体、原生 16 次迭代、原有摩擦与阻尼、全部原始关节和碰撞形状。实验通过局部资源或独立物理空间设置参数。复测时使用同一工况、同一步频，比对下表同一行中的父配置。跨步频时选同一配置。[完整全身对照](results/parameter_comparison.csv) · [逐关节对照，gzip 压缩的 CSV](results/comparison_joints.csv.gz)

| 父配置 | 实验名 | 单次变更 |
|---|---|---|
| baseline | iterations32、iterations64 | 该测试空间的解算迭代从 16 增至 32 或 64。 |
| baseline | priority2、priority4 | 全部关节的原生求解优先级由 1 改为 2 或 4。 |
| baseline | mass | 胸减 1 kg，左右前臂、左右脚分别加 0.25 kg，总质量和各段张量保持基线值。 |
| baseline | inertia、capsule_tensor | 前者将每段张量放大 25%。后者只把胶囊的包围盒近似换成均匀实心胶囊的解析张量。两项各自从基线开始。 |
| baseline | damping、erp20 | 多轴角限位阻尼由 1 降至 0.70，或回正系数由 0.50 降至 0.20。 |
| baseline | visc4、visc8、visc16 | 加入关节相对旋转的被动黏性耗散，衰减率分别为 4、8、16 s⁻¹。各段成对施加等大反向角冲量，力矩限幅为 24 N·m。 |
| baseline | bias15、bias35、friction、body_drag3 | 分别试验形状接触偏置 0.15 或 0.35、表面摩擦 0.50、全身节点角阻尼 3。 |
| baseline | axial、hip_adduction | 前者用有限位的原生六自由度关节模拟四个铰链；后者仅将左右髋向内侧的摆动限位收至 20°。 |
| baseline | slop2mm、persistence12mm | 空间允许接触穿透改为 2 mm，或接触保持距离改为 12 mm，空间参数有运行时读回。 |
| baseline | palms | 双手接触形状由盒改为直径 69 mm、高 133 mm 的胶囊，保留原质量、张量和手腕枢轴。 |
| baseline | rolling5mm、rolling15mm | 通过静态表面的实际法向冲量施加有限滚动阻力，力臂分别为 5、15 mm。自由飞行时该项为零。 |
| baseline | speculative | 单步预测形状接触，仅在自由飞行的形状可能接触时施加有限法向冲量。 |
| speculative | articulated、spec_no_ccd | 前者加入关节链与既有接触共同传力的被动冲量解算；后者只关闭原生 CCD。 |
| articulated | articulated_palms、coupled_no_ccd | 分别只换圆掌或只关闭原生 CCD。 |
| capsule_tensor | tensor_iter32、tensor_iter64 | 保持此次张量实验，单独增加测试空间迭代。 |
| palms | palms_iter32、palms_iter64、palms_rolling | 分别从圆掌开始改变迭代，或添加 15 mm 滚阻。 |
| palms_rolling | contact_iter32、contact_iter48、contact_iter64 | 保持圆掌及 15 mm 滚阻，改变原生迭代数。 |
| palms_rolling | contact_spec、contact_visc8、contact_damping、contact_bias35、contact_slop、contact_persistence、contact_drag、contact_friction | 一次试验仅叠加对应的预测、黏性、角限位阻尼、形状偏置、空间穿透、保持距离、节点角阻尼或摩擦变化。数值与上文同名实验一致。 |
| palms_rolling | contact_roll18、contact_roll22、contact_roll25、contact_roll30 | 仅将静态接触的滚阻力臂改为 18、22、25 或 30 mm。 |
| palms_rolling | contact_load10、30、60、100 | 对接触法向载荷作一阶滤波，时间常数单位 ms；失去接触立即清零，只在有静态表面接触时产生阻力。 |
| palms_rolling，或在其基础上仅换圆角足底 | contact_bearing015、035、070、140；foot_bearing015、035、070、140 | 在所有关节分别施加上限 0.15、0.35、0.70 或 1.40 N·m 的干摩擦。根据两个刚体的真实逆惯量限幅，冲量方向反对相对转动，大小至多足以将两者角速度拉齐。 |
| palms_rolling 或 foot_bearing140 | contact_stop10、30、90、180；foot_stop10、30、90、180 | 仅将 11 个原生多轴关节的被动角止挡力矩分别限至 10、30、90、180 N·m，四个铰链沿用原限位。注册关节后写入，避免引擎初始化覆盖该参数。 |
| foot_bearing140 | bearing35、38、40、42、45、50 | 根据相邻两段中较小的横截面半径调整干摩擦力矩上限，参考半径单位 mm。 |
| bearing40 | bearing40_iter12、14、18、20、24、32、48、64；bearing40_drag05、2、4 | 分别只变私有空间的求解迭代数，或只增加 0.5、2、4 s⁻¹ 的被动关节黏性耗散。 |
| foot_bearing140 | shoulder_stop45、90、150 | 仅将双肩原生角止挡力矩限至 45、90 或 150 N·m。 |
| contact_stop90 | ankle_stop30、180、300 | 除双踝外仍用 90 N·m，双踝上限分别改为 30、180、300 N·m。 |
| palms_rolling | contact_slow1、2、4、8 | 静态表面接触增加低速滚动阻力，附加力臂为 15 mm × exp(−ω²/ω₀²)，四组过渡速度分别为 1、2、4、8 rad/s。 |

### 原侧跌工况

| 配置 | 60 Hz 峰值锚距（cm） | 120 Hz 峰值锚距（cm） |
|---|---:|---:|
| 原始基线 | 10.93 | 6.39 |
| 32 次迭代 | 12.11 | 6.30 |
| 64 次迭代 | 7.30 | 14.30 |
| 改变质量分布 | 8.09 | 15.88 |
| 惯量放大 25% | 15.33 | 6.55 |
| 解析胶囊张量 | 8.72 | 5.48 |
| 多轴角限位阻尼 0.70 | 6.46 | 15.18 |
| 仅圆掌 | 7.54 | 6.98 |
| 仅 15 mm 滚阻 | 11.05 | 6.43 |
| 圆掌和 15 mm 滚阻 | 7.91 | 6.97 |

同一变量在两档步频下可产生方向相反的变化。峰值所在关节也可改变。数据支持离散步长、同时接触和限位求解共同影响传力。静态锚点配置、质量比或惯性张量均无法单独解释原来的两次峰值。[原工况逐帧取证](results/phase1_forensics.md)

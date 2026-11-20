extends RefCounted

const CAPTIONS := {
	"fire":"主动作","use":"交互","jump":"跳跃","crouch":"蹲下","sprint":"冲刺",
	"alternate":"副动作","more":"更多","inventory":"背包","map":"地图","pause_game":"暂停",
	"reload":"装填","flashlight":"提灯","shape":"形状","rotate":"旋转","journal":"委托","discard":"丢弃","offhand_use":"副手","swap_hands":"换手"}

const EXTRA := ["map","journal","flashlight","reload","shape","rotate","swap_hands","discard"]
static var active := OS.has_feature("android") or OS.has_feature("ios") or "--touch-controls" in OS.get_cmdline_user_args()

static func action_caption(id:String)->String:
	if id=="reload": return "装填"
	if id=="sprint": return "双推摇杆"
	if id in EXTRA: return "更多 → "+str(CAPTIONS[id])
	if CAPTIONS.has(id): return CAPTIONS[id]
	if id in ["up","down","left","right"]: return "移动摇杆"
	if id in ["slot_prev","slot_next"]: return "底部快捷栏"
	if id.begins_with("slot_"): return "快捷格 "+id.trim_prefix("slot_")
	return id

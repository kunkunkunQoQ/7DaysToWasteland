extends "res://tools/verify_lan_discovery.gd"

const SHAWL := "meme_shawl"
var received: Dictionary = {}
var captions: Array[String] = []

func listen_to_session() -> void:
	app.session.chat_received.connect(func(sender: String, words: String): received[words] = sender)
	app.session.shawl_spoke.connect(func(words: String): captions.append(words))

func signal_ready() -> void:
	var file := FileAccess.open(ticket,FileAccess.WRITE)
	file.store_line("ready")

func connect_guest() -> bool:
	if not check(app.network.connect_to("127.0.0.1",port)==OK,"guest connects to the chat host"): return false
	if not check(await until(func(): return app.session.replica),"guest receives world bootstrap"): return false
	listen_to_session()
	return true

func host() -> void:
	app.options.player_name = "营地房主"
	var config: Dictionary = app._default_config()
	config.terrain_revision = 2
	app._enter_world(config,{},1,false)
	var session: WastelandSession = app.session
	session.player.invulnerable = 300.0
	listen_to_session()
	if not check(app.network.listen(port)==OK,"host opens real ENet room"): return
	signal_ready()
	if not check(await until(func(): return received.has("河边见")),"host receives guest chat"): return
	var member: WastelandLan.MemberState = app.network.joined_members()[0]
	var identity := member.token
	check(received["河边见"]=="湖岸访客","host attributes guest chat to confirmed nickname")
	session.send_chat("收到")
	check(not session.achievements.unlocked("shiver_chat"),"two guest messages plus one host message do not unlock")
	if not check(await until(func(): return member.bag.count(SHAWL)==1),"guest earns the first copy"): return
	check(session.bag.count(SHAWL)==0 and session.achievements.unlocked("shiver_chat"),"world unlocks while host inventory stays unchanged")
	session.send_chat("我到了")
	session.send_chat("欢迎")
	if not check(session.bag.count(SHAWL)==1,"host earns a separate shawl"): return
	if not check(await until(func(): return received.has("字幕收到")),"guest confirms receipt of worn shawl caption"): return
	check(captions.any(func(words): return words.contains("湖岸访客")),"nearby host receives guest shawl caption with correct wearer")
	session.send_chat("可以重连")
	if not check(await until(func(): return not is_instance_valid(member.survivor)),"guest disconnects before rejoining"): return
	if not check(await until(func(): return received.has("重连三")),"host receives guest's remaining messages after reconnect"): return
	var returning: WastelandLan.MemberState = app.network.joined_members()[0]
	check(returning.token==identity and returning.bag.count(SHAWL)==1 and session.bag.count(SHAWL)==1,"rejoining guest retains one shawl, with no duplicate for either player")
	if not check(session.save_now(false)==OK,"host saves completed world"): return
	var saved := WastelandSave.read(1)
	check(saved.bag.counts.get(SHAWL,0)==1 and saved.guests[identity].bag.counts.get(SHAWL,0)==1 and saved.progress.achieved.has("shiver_chat"),"world checkpoint contains both private awards and shared achievement")
	session.send_chat("核对完成")
	if not check(await until(func(): return received.has("已结束")),"guest confirms final acknowledgement"): return
	check(await until(func(): return app.network.joined_members().is_empty()),"guest finishes and disconnects cleanly")

func guest() -> void:
	app.options.player_name = "湖岸访客"
	if not check(await until(func(): return FileAccess.file_exists(ticket)),"host announces listening port"): return
	if not await connect_guest(): return
	app.session.send_chat("出发")
	app.session.send_chat(" 出发 ")
	app.session.send_chat("河边见")
	if not check(await until(func(): return received.has("收到")),"guest receives host reply"): return
	check(received["收到"]=="营地房主" and received.get("出发")=="湖岸访客","guest sees both authors and the host echo")
	app.session.send_chat("到了")
	if not check(await until(func(): return app.session.bag.count(SHAWL)==1 and received.has("欢迎")),"guest receives their shawl and the host's third message"): return
	app.session.ui_command("quick_equip",[SHAWL])
	if not check(await until(func(): return captions.any(func(words): return words.contains("湖岸访客"))),"wearer receives their own caption over LAN"): return
	app.session.send_chat("字幕收到")
	if not check(await until(func(): return received.has("可以重连")),"host is ready for reconnect"): return
	app.leave_world()
	if not check(await until(func(): return app.session.preview_only),"guest returns to title"): return
	if not await connect_guest(): return
	check(app.session.bag.count(SHAWL)==1 and app.session.bag.is_worn(SHAWL),"reconnect restores equipped shawl")
	for words: String in ["重连一","重连二","重连三"]: app.session.send_chat(words)
	if not check(await until(func(): return received.has("核对完成")),"host confirms post-reconnect inventories"): return
	check(app.session.bag.count(SHAWL)==1,"replaying challenge never grants another shawl")
	app.session.send_chat("已结束")
	check(await until(func(): return received.has("已结束")),"guest receives last message echo")

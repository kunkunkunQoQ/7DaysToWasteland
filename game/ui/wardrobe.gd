extends RefCounted

const PROFILES := preload("res://game/core/survivor_profiles.gd")

static func player_name_input(parent: Control, game: Node) -> LineEdit:
	var row := WastelandUIStyle.line(parent)
	row.add_child(WastelandUIStyle.label("玩家昵称",16,WastelandUIStyle.MUTED))
	var edit := LineEdit.new()
	edit.name = "PlayerNameInput"
	edit.max_length = WastelandSettings.PLAYER_NAME_LIMIT
	edit.text = game.options.player_name
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.tooltip_text = "最多 12 个字，队友可以在你头顶看到这个昵称。"
	row.add_child(edit)
	var commit := func():
		game.set_player_name(edit.text)
		edit.text = game.options.player_name
	edit.text_submitted.connect(func(_value: String): commit.call())
	edit.focus_exited.connect(commit)
	return edit

static func picker(parent: Control, game: Node, avatar: WastelandPartyAvatar, changed: Callable = Callable()) -> void:
	var menu := OptionButton.new()
	menu.name = "OutfitPicker"
	var ids := WastelandPartyAvatar.OUTFITS.keys()
	for id in ids:
		menu.add_item("%s · %s" % [WastelandPartyAvatar.NAMES[id],WastelandPartyAvatar.OUTFITS[id]])
	menu.select(maxi(0,ids.find(game.options.appearance)))
	parent.add_child(menu)
	var note := WastelandUIStyle.label("",15,WastelandUIStyle.MUTED,true)
	var stats := WastelandUIStyle.label("",16,WastelandUIStyle.MINT,true)
	parent.add_child(note)
	parent.add_child(stats)
	var refresh := func(id: String):
		avatar.apply_outfit(id)
		note.text = "%s  /  %s" % [WastelandPartyAvatar.ORIGINS[id],WastelandPartyAvatar.STORIES[id]]
		note.tooltip_text = WastelandPartyAvatar.DESCRIPTIONS[id]
		var limits: Dictionary = PROFILES.STATS[id]
		stats.text = "生命 %d　耐力 %d　闭气 %d 秒" % [limits.health,limits.stamina,limits.breath]
		if changed.is_valid(): changed.call()
	refresh.call(game.options.appearance)
	menu.item_selected.connect(func(index: int):
		var id: String = ids[index]
		game.set_appearance(id)
		refresh.call(id))

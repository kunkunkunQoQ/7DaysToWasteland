extends RefCounted

static func observe(session:Node,species:String,form:String)->void:
	if not species in WastelandHordes.WILDLIFE: return
	_store(session,species,"observe","目击"+({"young":"幼年个体","local":"地方色个体"}.get(form,"成年个体")))

static func track(session:Node,trail:Dictionary)->void:
	var species:String=trail.get("species","")
	if species not in WastelandHordes.WILDLIFE: return
	var activity:String=trail.get("activity","")
	var evidence:="惊逃迹" if activity=="受惊疾行" else "觅食痕迹" if activity=="停步觅食" else "行走足迹"
	_store(session,species,evidence,trail.get("label",activity))

static func _store(session:Node,species:String,event:String,summary:String)->void:
	var records:Dictionary=session.progress.records
	if not records.has("nature_fieldnotes"): records.nature_fieldnotes={}
	if not records.nature_fieldnotes.has(species): records.nature_fieldnotes[species]={}
	var at:Vector3=session.player.global_position
	records.nature_fieldnotes[species][event]={"day":session.clock.day(),"time":session.clock.time_text(),
		"region":session.stream.generator.landform(at.x,at.z),"summary":summary}

static func lines(session:Node,species:String)->PackedStringArray:
	var log:Dictionary=session.progress.records.get("nature_fieldnotes",{}).get(species,{})
	var notes:=PackedStringArray()
	for key:String in ["observe","觅食痕迹","惊逃迹","行走足迹"]:
		if not log.has(key): continue
		var row:Dictionary=log[key]
		notes.append("第 %d 日 %s · %s · %s"%[row.day,row.time,row.region,row.summary])
	return notes

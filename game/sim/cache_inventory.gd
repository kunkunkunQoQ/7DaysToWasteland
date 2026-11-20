extends RefCounted

const CAPACITY:=24
# Per-viewer state: the owner's peer ID is 1; each guest has its own ID.
var actors: Dictionary={}
var mirrored:Array=[]

func model(s:Node,key:String)->Node3D:
	if key.is_empty() or key.length()>160: return null
	var coord:=key.get_slice(":",0).split(",")
	if coord.size()!=2 or not coord[0].is_valid_int() or not coord[1].is_valid_int(): return null
	var chunk:WastelandChunk=s.stream.active.get(Vector2i(int(coord[0]),int(coord[1])))
	if not is_instance_valid(chunk): return null
	var visual:Node3D=chunk.supply_caches.get(key)
	if not is_instance_valid(visual) or visual.is_queued_for_deletion(): return null
	var box:StaticBody3D=visual.get_parent()
	return visual if box.collision_layer!=0 and not box.is_queued_for_deletion() else null

func near(s:Node,visual:Node3D)->bool:
	return is_instance_valid(visual) and s.player.global_position.distance_squared_to(visual.global_position)<=36.0

func lids()->Array[String]:
	var ids:Array[String]=[]
	for key:String in actors.values():
		if key!="" and not ids.has(key): ids.append(key)
	return ids

func paint(s:Node,key:String,opened:bool)->void:
	var visual:=model(s,key)
	if visual: visual.set_opened(opened)

func apply_lids(s:Node,keys:Array)->void:
	for key:String in mirrored:
		if not keys.has(key): paint(s,key,false)
	for key:String in keys: paint(s,key,true)
	mirrored=keys.duplicate()

func leave(s:Node,peer:int)->void:
	var key:String=actors.get(peer,"")
	actors.erase(peer)
	if not key.is_empty() and not actors.values().has(key): paint(s,key,false)

func open(s:Node,body:StaticBody3D)->void:
	var key:String=body.get_meta("key")
	if s.replica or not near(s,model(s,key)): return
	leave(s,s.actor_peer_id)
	s._container_record(body)
	actors[s.actor_peer_id]=key
	s.stream.active[body.get_meta("cell")].sync_cache(key)
	paint(s,key,true)
	s.Patrol.opened_cache(s,body.get_meta("cell"))
	s._open_for_player("chest",key)

func occupied(s:Node,items:Dictionary)->int:
	var used:=0
	for id:String in items: used+=ceili(float(items[id])/s.bag.stack_size(id))
	return used

func room(s:Node,items:Dictionary,id:String)->int:
	var stack:int=s.bag.stack_size(id)
	return maxi(0,CAPACITY-occupied(s,items))*stack+posmod(-int(items.get(id,0)),stack)

func view(s:Node,key:String)->Dictionary:
	if s.replica:
		return s.replica_chest if key!="" and s.replica_chest.get("key","")==key else {}
	var visual:=model(s,key)
	if key=="" or actors.get(s.actor_peer_id,"")!=key or not near(s,visual): return {}
	var body:StaticBody3D=visual.get_parent()
	var record:Dictionary=s.stream.chunk_diff(body.get_meta("cell")).get("containers",{}).get(key,{})
	if not record.has("items"): return {}
	return {"key":key,"title":s._cache_title(body),"items":record.items.duplicate(),"slots":CAPACITY,"used":occupied(s,record.items)}

func move(s:Node,key:String,action:String,id:String,amount:int)->int:
	if s.replica or view(s,key).is_empty() or amount<1: return 0
	if action!="all" and (id=="" or not s.catalog.items.has(id)): return 0
	var body:StaticBody3D=model(s,key).get_parent()
	var record:Dictionary=s.stream.edit_chunk(body.get_meta("cell")).containers[key]
	var contents:Dictionary=record.items
	var deposited:Dictionary=record.get("stored",{})
	var moved:=0
	var found:=0
	match action:
		"put":
			moved=mini(amount,mini(s.bag.available_count(id),room(s,contents,id)))
			if moved<=0 or not s.bag.spend({id:moved}): return 0
			contents[id]=int(contents.get(id,0))+moved
			deposited[id]=int(deposited.get(id,0))+moved
			var ammo:String=s.catalog.items[id].get("ammo","")
			if ammo!="" and s.bag.count(id)==0 and s.bag.magazine.has(id):
				var rounds:int=s.bag.magazine[id]
				s.bag.magazine.erase(id)
				if rounds>0:
					s.award({ammo:rounds},s.player.global_position)
					s.notify("弹药已卸下 · "+s.catalog.title(ammo)+" ×"+str(rounds))
		"take","all":
			var ids:Array=contents.keys() if action=="all" else [id]
			for item:String in ids:
				var available:=int(contents.get(item,0))
				if available<=0: continue
				var take:int=s.bag.add(item,available if action=="all" else mini(amount,available))
				if take<=0: continue
				var rest:=available-take
				var own:=int(deposited.get(item,0))
				found+=mini(take,maxi(0,available-own))
				if own>rest: deposited[item]=rest
				if int(deposited.get(item,0))==0: deposited.erase(item)
				if rest>0: contents[item]=rest
				else: contents.erase(item)
				moved+=take
		_: return 0
	if deposited.is_empty(): record.erase("stored")
	else: record.stored=deposited
	if found>0:
		if not record.get("earned",false):
			s.gain(21,"loot")
			record.earned=true
		var region:String=body.get_meta("submerged_site","")
		if region!="" and not s.progress.records.has("recover_"+region):
			s.gain(45,"recover_"+region)
			s.notify("已记录水下遗址 · "+s._cache_title(body),4)
	s.stream.active[body.get_meta("cell")].sync_cache(key)
	return moved

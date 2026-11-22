package localenergy;
import com.google.gson.*;
import emu.grasscutter.command.*;
import emu.grasscutter.game.entity.*;
import emu.grasscutter.game.player.Player;
import emu.grasscutter.game.props.*;
import emu.grasscutter.game.props.ItemUseAction.ItemUseAddEnergy;
import emu.grasscutter.plugin.Plugin;
import emu.grasscutter.server.event.EventHandler;
import emu.grasscutter.server.event.game.SendPacketEvent;
import emu.grasscutter.server.event.game.ReceivePacketEvent;
import emu.grasscutter.server.event.player.PlayerUseSkillEvent;
import emu.grasscutter.server.event.player.PlayerObtainItemEvent;
import emu.grasscutter.net.packet.PacketOpcodes;
import emu.grasscutter.net.proto.EntityFightPropChangeReasonNotifyOuterClass.EntityFightPropChangeReasonNotify;
import emu.grasscutter.net.proto.PropChangeReasonOuterClass.PropChangeReason;
import emu.grasscutter.net.proto.AbilityInvokeEntryOuterClass.AbilityInvokeEntry;
import emu.grasscutter.net.proto.AbilityInvocationsNotifyOuterClass.AbilityInvocationsNotify;
import emu.grasscutter.net.proto.ClientAbilityChangeNotifyOuterClass.ClientAbilityChangeNotify;
import emu.grasscutter.net.proto.ClientAbilityInitFinishNotifyOuterClass.ClientAbilityInitFinishNotify;
import emu.grasscutter.net.proto.AbilityMetaModifierChangeOuterClass.AbilityMetaModifierChange;
import emu.grasscutter.net.proto.AbilityActionGenerateElemBallOuterClass.AbilityActionGenerateElemBall;
import emu.grasscutter.net.proto.AbilityActionSetRandomOverrideMapValueOuterClass.AbilityActionSetRandomOverrideMapValue;
import emu.grasscutter.net.proto.SceneEntityAppearNotifyOuterClass.SceneEntityAppearNotify;
import emu.grasscutter.data.GameData;
import emu.grasscutter.data.binout.AbilityModifier.AbilityModifierAction;
import emu.grasscutter.game.ability.Ability;
import java.nio.file.*;
import java.util.*;

/** Read-only energy diagnostics for local UID 10001. No mutation or additional network listeners. */
public final class LocalEnergyDiagnostics extends Plugin {
    static final Path ROOT=Path.of("E:\\Genshin-Local-Server");
    static final Gson JSON=new GsonBuilder().setPrettyPrinting().create();
    static LocalEnergyDiagnostics instance;
    final ArrayDeque<JsonObject> events=new ArrayDeque<>();
    volatile long watchUntil;
    static JsonArray team(Player p){
        var rows=new JsonArray();if(p==null||p.getTeamManager()==null)return rows;
        var manager=p.getTeamManager();var active=manager.getActiveTeam();
        for(int i=0;i<active.size();i++){
            var e=active.get(i);var a=e.getAvatar();var depot=a.getSkillDepot();var element=depot.getElementType();
            var row=new JsonObject();row.addProperty("avatarId",a.getAvatarId());row.addProperty("entityId",e.getId());row.addProperty("onField",i==manager.getCurrentCharacterIndex());
            row.addProperty("element",element.name());row.addProperty("chargeEfficiency",a.getFightProperty(FightProperty.FIGHT_PROP_CHARGE_EFFICIENCY));
            row.addProperty("entityChargeEfficiency",e.getFightProperty(FightProperty.FIGHT_PROP_CHARGE_EFFICIENCY));
            row.addProperty("energy",a.getFightProperty(element.getCurEnergyProp()));row.addProperty("maxEnergy",a.getFightProperty(element.getMaxEnergyProp()));
            rows.add(row);
        }return rows;
    }
    synchronized void record(JsonObject row){row.addProperty("time",java.time.Instant.now().toString());if(events.size()==1000)events.removeFirst();events.addLast(row);}
    static String abilityName(Ability a){return a!=null&&a.getData()!=null?a.getData().abilityName:null;}
    static String resolve(emu.grasscutter.net.proto.AbilityStringOuterClass.AbilityString s){return s.hasStr()?s.getStr():GameData.getAbilityHashes().get(s.getHash());}
    void incoming(Player p,AbilityInvokeEntry e){
        try{
            var scene=p.getScene();var entity=scene==null?null:scene.getEntityById(e.getEntityId());var h=e.getHead();
            Ability a=null;
            if(entity!=null){
                var m=entity.getInstancedModifiers().get(h.getInstancedModifierId());if(m!=null)a=m.getAbility();
                int n=h.getInstancedAbilityId()-1;if(a==null&&n>=0&&n<entity.getInstancedAbilities().size())a=entity.getInstancedAbilities().get(n);
            }
            var action=a!=null&&a.getData()!=null?a.getData().localIdToAction.get(h.getLocalId()):null;
            String type=e.getArgumentType().name();String name=abilityName(a);String modifier=null;
            boolean relevant=type.endsWith("GENERATE_ELEM_BALL")||type.contains("SET_RANDOM_OVERRIDE")
                    ||action!=null&&(action.type==AbilityModifierAction.Type.GenerateElemBall||action.type==AbilityModifierAction.Type.SetRandomOverrideMapValue);
            if(type.endsWith("MODIFIER_CHANGE")){
                var mc=AbilityMetaModifierChange.parseFrom(e.getAbilityData());String parent=resolve(mc.getParentAbilityName());
                var data=parent!=null?GameData.getAbilityData(parent):null;
                if(data!=null&&data.modifiers!=null){var names=new ArrayList<>(data.modifiers.keySet());
                    if(mc.getModifierLocalId()>=0&&mc.getModifierLocalId()<names.size())modifier=names.get(mc.getModifierLocalId());
                }
                if(parent!=null&&(parent.contains("DropBall")||parent.contains("GenerateBall")||parent.contains("ElemBall"))){relevant=true;name=parent;}
            }
            if(!relevant)return;
            var row=new JsonObject();row.addProperty("kind","skill-particle-invoke");row.addProperty("argument",type);
            row.addProperty("ability",name);row.addProperty("modifier",modifier);row.addProperty("entityId",e.getEntityId());
            row.addProperty("localId",h.getLocalId());row.addProperty("abilityId",h.getInstancedAbilityId());row.addProperty("modifierId",h.getInstancedModifierId());row.addProperty("targetId",h.getTargetId());
            row.addProperty("action",action!=null?action.type.name():null);
            row.addProperty("payloadBytes",e.getAbilityData().size());
            // Only relevant skill action payloads, never login/account packets; bounded to 512 bytes.
            row.addProperty("payloadBase64",Base64.getEncoder().encodeToString(e.getAbilityData().substring(0,Math.min(512,e.getAbilityData().size())).toByteArray()));
            if(action!=null&&a!=null){
                row.addProperty("configID",action.configID);
                if(action.baseEnergy!=null)row.addProperty("baseEnergy",action.baseEnergy.get(a));
                if(action.ratio!=null)row.addProperty("ratio",action.ratio.get(a));
                row.addProperty("overrideKey",action.overrideMapKey);
                row.add("specials",JSON.toJsonTree(new TreeMap<>(a.getAbilitySpecials())));
            }
            if(type.endsWith("GENERATE_ELEM_BALL")||action!=null&&action.type==AbilityModifierAction.Type.GenerateElemBall){
                var v=AbilityActionGenerateElemBall.parseFrom(e.getAbilityData());row.addProperty("parsedPos",v.getPos().toString());row.addProperty("unknownFields",v.getUnknownFields().toString());
            }
            if(action!=null&&action.type==AbilityModifierAction.Type.SetRandomOverrideMapValue){
                var v=AbilityActionSetRandomOverrideMapValue.parseFrom(e.getAbilityData());row.addProperty("parsedRandom",v.getRandomValue());row.addProperty("unknownFields",v.getUnknownFields().toString());
            }
            record(row);
        }catch(Exception ex){var row=new JsonObject();row.addProperty("kind","skill-particle-parse-error");row.addProperty("error",ex.toString());record(row);}
    }
    @Override public void onEnable(){
        try{
            if(!Path.of("").toAbsolutePath().normalize().equals(ROOT.resolve("server")))throw new IllegalStateException("Expected E: local-server working directory");
            Files.createDirectories(ROOT.resolve("run/energy-audits"));instance=this;
            CommandMap.getInstance().registerCommand("localenergyaudit",new AuditCommand());
            EventHandler.newHandler(this,ReceivePacketEvent.class,event->{
                if(System.currentTimeMillis()>watchUntil)return;var p=event.getGameSession().getPlayer();if(p==null||p.getUid()!=10001)return;
                try{List<AbilityInvokeEntry> invokes;
                    if(event.getPacketId()==PacketOpcodes.AbilityInvocationsNotify)invokes=AbilityInvocationsNotify.parseFrom(event.getPacketData()).getInvokesList();
                    else if(event.getPacketId()==PacketOpcodes.ClientAbilityChangeNotify)invokes=ClientAbilityChangeNotify.parseFrom(event.getPacketData()).getInvokesList();
                    else if(event.getPacketId()==PacketOpcodes.ClientAbilityInitFinishNotify)invokes=ClientAbilityInitFinishNotify.parseFrom(event.getPacketData()).getInvokesList();
                    else return;for(var invoke:invokes)incoming(p,invoke);
                }catch(Exception ignored){}
            });
            EventHandler.newHandler(this,PlayerUseSkillEvent.class,event->{
                if(System.currentTimeMillis()>watchUntil||event.getPlayer().getUid()!=10001)return;
                var row=new JsonObject();row.addProperty("kind","skill-start");row.addProperty("avatarId",event.getAvatar().getAvatarId());row.addProperty("skillId",event.getSkillData().getId());record(row);
            });
            EventHandler.newHandler(this,SendPacketEvent.class,event->{
                if(System.currentTimeMillis()>watchUntil||event.getPacket().getOpcode()!=PacketOpcodes.SceneEntityAppearNotify)return;
                var p=event.getGameSession().getPlayer();if(p==null||p.getUid()!=10001||p.getScene()==null)return;
                try{var n=SceneEntityAppearNotify.parseFrom(event.getPacket().getData());for(var entity:n.getEntityListList()){
                    var live=p.getScene().getEntityById(entity.getEntityId());if(!(live instanceof EntityItem item))continue;
                    var data=item.getItemData();if(data==null||data.getItemUseActions()==null||data.getItemUseActions().stream().noneMatch(x->x instanceof ItemUseAddEnergy))continue;
                    var row=new JsonObject();row.addProperty("kind","particle-spawn");row.addProperty("entityId",item.getId());row.addProperty("itemId",item.getItem().getItemId());row.addProperty("count",item.getCount());row.addProperty("position",item.getPosition().toString());record(row);
                }}catch(Exception ignored){}
            });
            EventHandler.newHandler(this,PlayerObtainItemEvent.class,event->{
                if(System.currentTimeMillis()>watchUntil||event.getPlayer().getUid()!=10001)return;
                var item=event.getItem();var d=item.getItemData();if(d==null||d.getItemUseActions()==null||d.getItemUseActions().stream().noneMatch(a->a instanceof ItemUseAddEnergy))return;
                var row=new JsonObject();row.addProperty("kind","pickup-after-use");row.addProperty("itemId",item.getItemId());row.addProperty("count",item.getCount());row.add("team",team(event.getPlayer()));record(row);
            });
            EventHandler.newHandler(this,SendPacketEvent.class,event->{
                if(System.currentTimeMillis()>watchUntil||event.getPacket().getOpcode()!=PacketOpcodes.EntityFightPropChangeReasonNotify)return;
                var p=event.getGameSession().getPlayer();if(p==null||p.getUid()!=10001)return;
                try{var n=EntityFightPropChangeReasonNotify.parseFrom(event.getPacket().getData());
                    if(n.getReason()!=PropChangeReason.PropChangeReason_PROP_CHANGE_ENERGY_BALL)return;
                    var row=new JsonObject();row.addProperty("kind","particle-energy-delta");row.addProperty("entityId",n.getEntityId());row.addProperty("propId",n.getPropType());row.addProperty("delta",n.getPropDelta());record(row);
                }catch(Exception ignored){}
            });
            var ready=new JsonObject();ready.addProperty("pid",ProcessHandle.current().pid());ready.addProperty("readOnly",true);ready.addProperty("uid",10001);ready.addProperty("skillParticleTracing",true);
            Files.writeString(ROOT.resolve("run/local-energy-diagnostics-ready.json"),JSON.toJson(ready));getLogger().info("Read-only energy diagnostics ready, UID10001 only; event capture off until requested");
        }catch(Exception e){throw new IllegalStateException(e);}
    }
    @Override public void onDisable(){CommandMap.getInstance().unregisterCommand("localenergyaudit");watchUntil=0;instance=null;}
    @Command(label="localenergyaudit",permission="server.energy.audit",permissionTargeted="server.energy.audit")
    static final class AuditCommand implements CommandHandler {
        @Override public void execute(Player sender,Player target,List<String> args){
            var self=instance;if(self==null)return;
            String token=args.isEmpty()?UUID.randomUUID().toString().replace("-",""):args.get(0);
            if(!token.matches("[a-f0-9]{32}"))return;
            var out=new JsonObject();out.addProperty("time",java.time.Instant.now().toString());out.addProperty("readOnly",true);
            try{
                if(target==null||target.getUid()!=10001||(sender!=null&&sender.getUid()!=10001))throw new IllegalArgumentException("Only local UID10001");
                if(args.size()>1){int seconds=Integer.parseInt(args.get(1));if(seconds<0||seconds>120)throw new IllegalArgumentException("Watch seconds 0..120");synchronized(self){self.events.clear();self.watchUntil=System.currentTimeMillis()+seconds*1000L;}}
                out.addProperty("ok",true);out.add("team",team(target));out.addProperty("watchUntilMillis",self.watchUntil);
                synchronized(self){out.add("recentEvents",JSON.toJsonTree(new ArrayList<>(self.events)));}
            }catch(Exception e){out.addProperty("ok",false);out.addProperty("error",e.getMessage());}
            try{Path path=ROOT.resolve("run/energy-audits/"+token+".json");Path tmp=path.resolveSibling(path.getFileName()+".tmp");Files.writeString(tmp,JSON.toJson(out));Files.move(tmp,path,StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);CommandHandler.sendMessage(sender,"Local read-only energy audit written: "+token);}catch(Exception e){self.getLogger().warn("Energy audit write failed: {}",e.toString());}
        }
    }
}

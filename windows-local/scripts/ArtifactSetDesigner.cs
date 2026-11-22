using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using System.Diagnostics;
using System.ComponentModel;
using System.Text;

class ArtifactSetDesigner : UserControl {
    readonly string root;readonly ArtifactCatalog catalog;readonly JavaScriptSerializer json=new JavaScriptSerializer(){MaxJsonLength=30000000};
    readonly List<ArtifactDesigner> editors=new List<ArtifactDesigner>();readonly List<ComboBox> mains=new List<ComboBox>();
    ComboBox sets,stars,mode,presets;TextBox search,preview,presetName;NumericUpDown level;Label note;Button generate,save,load,retry;
    FlowLayoutPanel header;TabControl parts;ArtifactSetRequest current;bool updating,busy,externalBusy;string pendingToken;
    public event Action<bool> BusyChanged;
    public bool IsBusy {get{return busy;}}
    public void SetExternalBusy(bool value){externalBusy=value;RefreshPreview();}
    public ArtifactSetDesigner(string installationRoot){
        root=installationRoot;catalog=ArtifactMath.Load(root);Dock=DockStyle.Fill;
        var layout=new TableLayoutPanel(){Dock=DockStyle.Fill,RowCount=3,ColumnCount=1,Padding=new Padding(10,6,10,6)};
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,125));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,185));
        header=Flow();var select=Row(38);search=new TextBox(){Width=130};sets=Combo(270);stars=Combo(55);level=new NumericUpDown(){Minimum=0,Maximum=20,Value=20,Width=62};mode=Combo(150);mode.Items.AddRange(new object[]{"标准范围","自由测试（超规格）"});mode.SelectedIndex=0;
        select.Controls.Add(Caption("套装搜索"));select.Controls.Add(search);select.Controls.Add(sets);select.Controls.Add(Caption("星级"));select.Controls.Add(stars);select.Controls.Add(Caption("等级＋"));select.Controls.Add(level);select.Controls.Add(mode);header.Controls.Add(select);
        var quick=Row(42);string[] names={"花","羽","沙","杯","冠"};
        for(int i=0;i<5;i++){int index=i;quick.Controls.Add(Caption(names[i]));var combo=Combo(174);mains.Add(combo);quick.Controls.Add(combo);combo.SelectedIndexChanged+=delegate{if(!updating&&combo.SelectedItem!=null){parts.SelectedIndex=index;editors[index].ChooseMain(((ArtifactMain)combo.SelectedItem).prop);}};}
        header.Controls.Add(quick);header.Controls.Add(new Label(){Width=1120,Height=42,Text="上方分别选择五个部位的主属性；下方切换部位定制各自副词条。五件均来自同一套装，各1件。\n点击生成直接发放，无预览确认或成功确定弹窗；只新增、不覆盖、不自动装备。切换套装/星级/等级/模式会重置五件配置。",ForeColor=Color.DimGray});layout.Controls.Add(header,0,0);
        parts=new TabControl(){Dock=DockStyle.Fill};string[] partNames={"生之花","死之羽","时之沙","空之杯","理之冠"};
        for(int i=0;i<5;i++){var editor=new ArtifactDesigner(root,true,catalog);editors.Add(editor);var tab=new TabPage(partNames[i]);tab.Controls.Add(editor);parts.TabPages.Add(tab);editor.RequestChanged+=delegate{if(!updating)RefreshPreview();};}layout.Controls.Add(parts,0,1);
        var footer=Flow();preview=new TextBox(){Width=1120,Height=64,Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical};footer.Controls.Add(preview);
        var actions=Row(36);generate=Button("一键生成五件套",190);retry=Button("核对未完成请求",170);actions.Controls.Add(generate);actions.Controls.Add(retry);actions.Controls.Add(new Label(){Text="需localtest / UID10001进入世界；每次点击新增五件，重复点击会再生成一套。",AutoSize=true,Margin=new Padding(8,6,0,0)});footer.Controls.Add(actions);
        var recipes=Row(36);presetName=new TextBox(){Width=190,Text="我的五件套"};save=Button("保存五件配方",135);presets=Combo(280);load=Button("载入五件配方",135);recipes.Controls.Add(presetName);recipes.Controls.Add(save);recipes.Controls.Add(presets);recipes.Controls.Add(load);footer.Controls.Add(recipes);
        note=new Label(){Width=1120,Height=42,ForeColor=Color.DarkBlue,Text="未发放任何物品。生成进度与成功结果会显示在这里。"};footer.Controls.Add(note);layout.Controls.Add(footer,0,2);Controls.Add(layout);
        search.TextChanged+=delegate{if(!updating)FillSets();};sets.SelectedIndexChanged+=delegate{if(!updating)FillStars();};stars.SelectedIndexChanged+=delegate{if(!updating){updating=true;level.Maximum=(int)stars.SelectedItem==4?16:20;if(level.Value>level.Maximum)level.Value=level.Maximum;updating=false;ResetEditors();}};
        level.ValueChanged+=delegate{if(!updating)ResetEditors();};mode.SelectedIndexChanged+=delegate{if(!updating)ResetEditors();};generate.Click+=delegate{Generate(false);};retry.Click+=delegate{Generate(true);};save.Click+=delegate{SavePreset();};load.Click+=delegate{LoadPreset();};FillSets();RefreshPresets();
    }
    static FlowLayoutPanel Flow(){return new FlowLayoutPanel(){Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,Margin=new Padding(0)};}
    static FlowLayoutPanel Row(int height){return new FlowLayoutPanel(){Width=1120,Height=height,WrapContents=false,Margin=new Padding(0)};}
    static Label Caption(string text){return new Label(){Text=text,AutoSize=true,Margin=new Padding(2,5,5,0)};}
    static ComboBox Combo(int width){return new ComboBox(){Width=width,DropDownStyle=ComboBoxStyle.DropDownList};}
    static Button Button(string text,int width){return new Button(){Text=text,Width=width,Height=31};}
    bool FullSet(int id,int rarity){return ArtifactMath.Slots.All(slot=>catalog.pieces.Any(p=>p.setId==id&&p.stars==rarity&&p.slot==slot));}
    void FillSets(){int old=(sets.SelectedItem as ArtifactSet)==null?15020:((ArtifactSet)sets.SelectedItem).id;updating=true;sets.Items.Clear();foreach(var s in catalog.sets.Where(s=>(FullSet(s.id,4)||FullSet(s.id,5))&&(s.name.Contains(search.Text.Trim())||s.id.ToString().Contains(search.Text.Trim()))))sets.Items.Add(s);sets.SelectedItem=sets.Items.Cast<ArtifactSet>().FirstOrDefault(s=>s.id==old);if(sets.Items.Count>0&&sets.SelectedIndex<0)sets.SelectedIndex=0;updating=false;FillStars();}
    void FillStars(){updating=true;stars.Items.Clear();var set=sets.SelectedItem as ArtifactSet;if(set!=null)foreach(int n in new[]{4,5})if(FullSet(set.id,n))stars.Items.Add(n);if(stars.Items.Count>0)stars.SelectedIndex=stars.Items.Count-1;level.Maximum=stars.SelectedItem!=null&&(int)stars.SelectedItem==4?16:20;if(level.Value>level.Maximum)level.Value=level.Maximum;updating=false;ResetEditors();}
    void ResetEditors(){var set=sets.SelectedItem as ArtifactSet;if(set==null||stars.SelectedItem==null){current=null;RefreshPreview();return;}updating=true;try{for(int i=0;i<5;i++)editors[i].ApplyRequest(ArtifactMath.Default(catalog,set.id,ArtifactMath.Slots[i],(int)stars.SelectedItem,(int)level.Value,mode.SelectedIndex==0?"standard":"free"));}finally{updating=false;}RefreshMainBoxes();RefreshPreview();}
    void RefreshMainBoxes(){updating=true;for(int i=0;i<5;i++){mains[i].Items.Clear();foreach(var m in editors[i].AvailableMains)mains[i].Items.Add(m);mains[i].SelectedItem=editors[i].AvailableMains.FirstOrDefault(m=>m.prop==editors[i].CurrentMainProp);}updating=false;}
    void RefreshPreview(){if(preview==null)return;current=null;try{if(sets.SelectedItem==null||stars.SelectedItem==null)throw new Exception("请选择完整五部位套装。");var batch=new ArtifactSetRequest();foreach(var e in editors){if(e.CurrentRequest==null)throw new Exception("有部位配置尚未有效，请检查各部位的副词条预算。");batch.pieces.Add(e.CurrentRequest);}ArtifactMath.ValidateSet(catalog,batch);current=batch;
            preview.Text=String.Join("\r\n",batch.pieces.Select(r=>{var p=catalog.pieces.First(x=>x.id==r.itemId);var m=p.mains.First(x=>x.id==r.mainPropId);return p.slotName+"："+m.label+" "+ArtifactMath.Display(m.values[r.level],m.percent)+"；"+p.stars+"★ +"+r.level+"；副词条贡献 "+r.affixes.Sum(a=>a.count);}));preview.ForeColor=Color.Black;
        }catch(Exception e){preview.Text="请调整配置："+e.Message;preview.ForeColor=Color.Firebrick;}
        updating=true;for(int i=0;i<5;i++)mains[i].SelectedItem=mains[i].Items.Cast<ArtifactMain>().FirstOrDefault(m=>m.prop==editors[i].CurrentMainProp);updating=false;
        bool idle=!busy&&!externalBusy;generate.Enabled=current!=null&&idle&&pendingToken==null;retry.Enabled=idle&&pendingToken!=null;save.Enabled=current!=null&&idle;load.Enabled=idle;header.Enabled=idle;parts.Enabled=idle;
    }
    void RefreshPresets(){presets.Items.Clear();var folder=Path.Combine(root,"presets\\artifact-sets");Directory.CreateDirectory(folder);foreach(var f in Directory.GetFiles(folder,"*.json").OrderByDescending(File.GetLastWriteTimeUtc))try{var d=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(f));presets.Items.Add(new PresetChoice(){file=f,title=Convert.ToString(d["title"])});}catch{}if(presets.Items.Count>0)presets.SelectedIndex=0;}
    void SavePreset(){if(current==null)return;try{var title=presetName.Text.Trim();if(title.Length<1||title.Length>70)throw new Exception("配方名填1–70个字符。");File.WriteAllText(Path.Combine(root,"presets\\artifact-sets",Guid.NewGuid().ToString("N")+".json"),json.Serialize(new Dictionary<string,object>(){{"title",title},{"data",current}}),new UTF8Encoding(false));RefreshPresets();note.Text="五件配方已保存到E盘，未发放物品。";}catch(Exception e){note.Text=e.Message;}}
    void LoadPreset(){var chosen=presets.SelectedItem as PresetChoice;if(chosen==null)return;try{var d=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(chosen.file));var batch=json.Deserialize<ArtifactSetRequest>(json.Serialize(d["data"]));ArtifactMath.ValidateSet(catalog,batch);var first=batch.pieces[0];var p=catalog.pieces.First(x=>x.id==first.itemId);search.Text="";updating=true;sets.SelectedItem=sets.Items.Cast<ArtifactSet>().First(x=>x.id==p.setId);updating=false;FillStars();updating=true;stars.SelectedItem=p.stars;level.Maximum=p.stars==4?16:20;level.Value=first.level;mode.SelectedIndex=first.mode=="standard"?0:1;for(int i=0;i<5;i++)editors[i].ApplyRequest(batch.pieces.First(r=>catalog.pieces.First(x=>x.id==r.itemId).slot==ArtifactMath.Slots[i]));presetName.Text=chosen.title;updating=false;RefreshMainBoxes();RefreshPreview();note.Text="已载入五件的完整主副词条配方，未发放物品。";}catch(Exception e){updating=false;note.Text="配方读取问题："+e.Message;}}
    void Generate(bool resume){if(busy||externalBusy||(!resume&&current==null)||(resume&&pendingToken==null))return;string token=pendingToken;
        if(!resume){token=Guid.NewGuid().ToString("N");Directory.CreateDirectory(Path.Combine(root,"run\\artifact-requests"));File.WriteAllText(Path.Combine(root,"run\\artifact-requests",token+".json"),json.Serialize(current),new UTF8Encoding(false));pendingToken=token;}
        busy=true;if(BusyChanged!=null)BusyChanged(true);RefreshPreview();note.Text="正在生成五个部位并核对存档，请勿同时手动发放。请求："+token;
        var worker=new BackgroundWorker();worker.DoWork+=delegate(object sender,DoWorkEventArgs e){var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32\\WindowsPowerShell\\v1.0\\powershell.exe"),"-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"scripts\\artifact-control.ps1")+"\" -RequestId "+token){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8,WorkingDirectory=root};info.EnvironmentVariables["PSModulePath"]=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32\\WindowsPowerShell\\v1.0\\Modules");using(var p=Process.Start(info)){var o=p.StandardOutput.ReadToEndAsync();var err=p.StandardError.ReadToEndAsync();p.WaitForExit();File.WriteAllText(Path.Combine(root,"logs\\artifact-set-ui.log"),o.Result+Environment.NewLine+err.Result,Encoding.UTF8);if(p.ExitCode!=0)throw new Exception((err.Result.Length>1200?err.Result.Substring(0,1200):err.Result)+"\n日志："+Path.Combine(root,"logs\\artifact-set-ui.log"));e.Result=o.Result;}};
        worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e){busy=false;if(BusyChanged!=null)BusyChanged(false);if(e.Error!=null){note.Text="五件套尚未全部确认；可能已有部分生成。请核对日志，使用同一请求核对按钮，先不要新建一套。";MessageBox.Show(e.Error.Message,"五件套生成问题",MessageBoxButtons.OK,MessageBoxIcon.Warning);}else try{var receipt=json.Deserialize<ArtifactReceipt>(((string)e.Result).Trim());if(!receipt.ok||receipt.added!=5)throw new Exception("五件回执不完整");pendingToken=null;note.Text="生成完成：五个部位各1件，主副词条与存档均已核对；没有覆盖或自动装备。请求："+token;}catch(Exception ex){note.Text="回执核对问题："+ex.Message+"；先不要再次新建一套。";}RefreshPreview();worker.Dispose();};worker.RunWorkerAsync();
    }
}

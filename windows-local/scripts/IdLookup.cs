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
using System.Threading.Tasks;

class IdEntry { public string kind,name,type,@internal,command; public int id,stars; public bool named; }
class EditReceipt { public bool ok; public int changed,matched,skipped,unchanged; public string backup,error; }
class IdLookup : Form {
    readonly string root; readonly List<IdEntry> entries;
    TextBox search,command; ComboBox category; CheckBox verified;
    DataGridView table; Label status,selected; NumericUpDown constellation,refinement,weaponQuantity,weaponLevel;
    readonly List<Button> actionButtons=new List<Button>(); bool busy;TabControl tabs;ArtifactDesigner artifactDesigner;ArtifactSetDesigner artifactSetDesigner;
    static readonly string[] Categories={"全部","角色（全部）","四星角色","五星角色","武器（全部）","四星武器","五星武器"};
    public IdLookup() {
        root=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"..",".."));
        Text="原神本地测试 · 角色武器与圣遗物管理"; ClientSize=new Size(1220,800); MinimumSize=new Size(1130,650);
        StartPosition=FormStartPosition.CenterScreen; Font=new Font("Microsoft YaHei UI",10); AutoScaleMode=AutoScaleMode.Dpi;
        try { Icon=Icon.ExtractAssociatedIcon(Path.Combine(root,"client\\Genshin-7.1-CN\\YuanShen.exe")); } catch {}
        entries=new JavaScriptSerializer(){MaxJsonLength=4000000}.Deserialize<List<IdEntry>>(File.ReadAllText(Path.Combine(root,"catalog\\items.json")));
        var filters=PanelRow(52); filters.Controls.Add(Caption("搜索名称或ID"));
        search=new TextBox(){Width=330}; category=new ComboBox(){Width=155,DropDownStyle=ComboBoxStyle.DropDownList};
        category.Items.AddRange(Categories); category.SelectedIndex=0;
        verified=new CheckBox(){Text="只显示已核对中文名",Checked=true,AutoSize=true,Margin=new Padding(14,4,0,0)};
        filters.Controls.Add(search);filters.Controls.Add(Caption("分类"));filters.Controls.Add(category);filters.Controls.Add(verified);
        var grants=PanelRow(48);
        AddButton(grants,"补齐角色＋武器",185,delegate{Grant("fill-all");});
        AddButton(grants,"只补齐角色",140,delegate{Grant("fill-missing");});
        AddButton(grants,"只补齐武器",140,delegate{Grant("fill-weapons");});
        var copy=new Button(){Text="复制选中发放指令",Width=185,Height=35};
        copy.Click+=delegate{if(!String.IsNullOrEmpty(command.Text))Clipboard.SetText(command.Text);};grants.Controls.Add(copy);
        var quick=PanelRow(48);
        AddButton(quick,"四星角色全部满命",195,delegate{Edit("avatar","stars4",6,"所有已拥有的四星角色 → 6命（不受搜索框影响）");});
        AddButton(quick,"五星角色全部满命",195,delegate{Edit("avatar","stars5",6,"所有已拥有的五星角色 → 6命（不受搜索框影响）");});
        AddButton(quick,"四星武器全部满精炼",210,delegate{Edit("weapon","stars4",5,"所有已拥有的四星武器 → 精炼5（五星武器不变，不受搜索框影响）");});
        AddButton(quick,"全部武器满精炼",195,delegate{Edit("weapon","all",5,"所有已拥有且支持精炼的武器 → 精炼5（不受搜索框影响）");});
        AddButton(quick,"撤销上一次修改",185,Undo);
        var edits=PanelRow(145);
        selected=new Label(){Text="选中：—",AutoSize=false,Width=1170,Height=25,Margin=new Padding(0,0,0,2)};
        edits.Controls.Add(selected);edits.SetFlowBreak(selected,true);
        edits.Controls.Add(Caption("命座")); constellation=new NumericUpDown(){Minimum=0,Maximum=6,Value=6,Width=60};edits.Controls.Add(constellation);
        AddButton(edits,"设定选中角色",155,delegate{SelectedEdit("avatar",(int)constellation.Value);});
        AddButton(edits,"筛选内角色批量设置",200,delegate{FilteredEdit("avatar",(int)constellation.Value);});
        edits.Controls.Add(Caption("精炼")); refinement=new NumericUpDown(){Minimum=1,Maximum=5,Value=5,Width=60};edits.Controls.Add(refinement);
        AddButton(edits,"设定选中武器",155,delegate{SelectedEdit("weapon",(int)refinement.Value);});
        AddButton(edits,"筛选内武器批量设置",200,delegate{FilteredEdit("weapon",(int)refinement.Value);});
        edits.SetFlowBreak(edits.Controls[edits.Controls.Count-1],true);
        edits.Controls.Add(Caption("新增武器数量"));weaponQuantity=new NumericUpDown(){Minimum=1,Maximum=100,Value=1,Width=70};edits.Controls.Add(weaponQuantity);
        edits.Controls.Add(Caption("新增武器等级"));weaponLevel=new NumericUpDown(){Minimum=1,Maximum=90,Value=90,Width=70};edits.Controls.Add(weaponLevel);
        AddButton(edits,"新增选中武器",180,AddSelectedWeapon);
        edits.Controls.Add(new Label(){Text="按上方精炼值生成；数量是额外新增，不是背包总数。",AutoSize=true,Margin=new Padding(12,7,0,0)});
        weaponQuantity.ValueChanged+=delegate{UpdateSelection();};weaponLevel.ValueChanged+=delegate{UpdateSelection();};refinement.ValueChanged+=delegate{UpdateSelection();};
        table=new DataGridView(){Dock=DockStyle.Fill,AllowUserToAddRows=false,AllowUserToDeleteRows=false,ReadOnly=true,MultiSelect=false,
            SelectionMode=DataGridViewSelectionMode.FullRowSelect,AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill,RowHeadersVisible=false,
            BackgroundColor=Color.White,BorderStyle=BorderStyle.None};
        foreach(string header in new[]{"分类","中文名称","ID代码","武器类型","星级","名称状态","默认指令示例（新增以底部参数为准）"})table.Columns.Add(header,header);
        table.Columns[0].FillWeight=45;table.Columns[1].FillWeight=125;table.Columns[2].FillWeight=80;table.Columns[3].FillWeight=75;
        table.Columns[4].FillWeight=45;table.Columns[5].FillWeight=75;table.Columns[6].FillWeight=210;
        var bottom=new Panel(){Dock=DockStyle.Bottom,Height=101,Padding=new Padding(12,7,12,4)};
        command=new TextBox(){Dock=DockStyle.Top,ReadOnly=true};status=new Label(){Dock=DockStyle.Fill,AutoEllipsis=true,Padding=new Padding(0,8,0,0)};
        bottom.Controls.Add(status);bottom.Controls.Add(command);
        Controls.Add(table);Controls.Add(bottom);Controls.Add(edits);Controls.Add(quick);Controls.Add(grants);Controls.Add(filters);
        table.SelectionChanged+=delegate{UpdateSelection();};search.TextChanged+=delegate{RefreshRows();};
        category.SelectedIndexChanged+=delegate{RefreshRows();};verified.CheckedChanged+=delegate{RefreshRows();};
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(busy&&MessageBox.Show("操作正在进行，关闭窗口后会继续在后台执行。仍要关闭吗？","本地测试",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)e.Cancel=true;};
        var existing=Controls.Cast<Control>().ToArray();Controls.Clear();tabs=new TabControl(){Dock=DockStyle.Fill};
        var management=new TabPage("角色 / 武器");management.Controls.AddRange(existing);
        var artifacts=new TabPage("圣遗物单件");artifactDesigner=new ArtifactDesigner(root);artifacts.Controls.Add(artifactDesigner);
        var artifactSets=new TabPage("圣遗物五件套");artifactSetDesigner=new ArtifactSetDesigner(root);artifactSets.Controls.Add(artifactSetDesigner);
        artifactDesigner.BusyChanged+=delegate(bool value){busy=value;foreach(var b in actionButtons)b.Enabled=!value;artifactSetDesigner.SetExternalBusy(value);};
        artifactSetDesigner.BusyChanged+=delegate(bool value){busy=value;foreach(var b in actionButtons)b.Enabled=!value;artifactDesigner.SetExternalBusy(value);};
        tabs.TabPages.Add(management);tabs.TabPages.Add(artifacts);tabs.TabPages.Add(artifactSets);Controls.Add(tabs);
        RefreshRows();
    }
    static FlowLayoutPanel PanelRow(int height) { return new FlowLayoutPanel(){Dock=DockStyle.Top,Height=height,Padding=new Padding(12,7,0,0),WrapContents=true}; }
    static Label Caption(string text) { return new Label(){Text=text,AutoSize=true,Margin=new Padding(0,5,8,0)}; }
    void AddButton(FlowLayoutPanel p,string title,int width,Action action) {var b=new Button(){Text=title,Width=width,Height=35};b.Click+=delegate{action();};actionButtons.Add(b);p.Controls.Add(b);}
    bool InCategory(IdEntry e) {
        switch(category.SelectedIndex) {
            case 1:return e.kind=="角色";case 2:return e.kind=="角色"&&e.stars==4;case 3:return e.kind=="角色"&&e.stars==5;
            case 4:return e.kind=="武器";case 5:return e.kind=="武器"&&e.stars==4;case 6:return e.kind=="武器"&&e.stars==5;default:return true;
        }
    }
    void RefreshRows() {
        if(table==null)return;table.Rows.Clear();string q=search.Text.Trim();
        foreach(var e in entries.Where(e=>(!verified.Checked||e.named)&&InCategory(e)&&(q.Length==0||(e.name??"").IndexOf(q,StringComparison.OrdinalIgnoreCase)>=0||e.id.ToString().Contains(q)||(e.@internal??"").IndexOf(q,StringComparison.OrdinalIgnoreCase)>=0))) {
            int i=table.Rows.Add(e.kind,e.name,e.id,e.type,e.stars>0?e.stars+"★":"",e.named?"已核对":"内部名/未确认",e.command);table.Rows[i].Tag=e;
        }
        if(table.Rows.Count>0)table.Rows[0].Selected=true;UpdateSelection();
        if(!busy)status.Text="当前显示 "+table.Rows.Count+" 项。修改需 localtest（UID10001）进入世界；已有角色/武器原地设置，保留等级、基础天赋、圣遗物与装备。\n同ID武器的全部副本一起改精炼；不支持精炼的武器自动跳过。每次修改先备份；降低命座可能短暂重载场景。";
    }
    IdEntry Selection() {return table!=null&&table.SelectedRows.Count>0?table.SelectedRows[0].Tag as IdEntry:null;}
    void UpdateSelection() {
        var e=Selection();if(command==null||selected==null)return;
        command.Text=e==null?"":e.kind=="武器"?"give @10001 "+e.id+" lv"+(int)weaponLevel.Value+" r"+(int)refinement.Value+" x"+(int)weaponQuantity.Value:e.command;
        selected.Text=e==null?"选中：—":"选中："+e.name+" · "+e.id+" · "+e.stars+"★ · "+e.kind+"（下面的数值是准备设置的目标，不代表当前存档数值）";
    }
    void SelectedEdit(string kind,int level) {
        var e=Selection();string label=kind=="avatar"?"角色":"武器";
        if(e==null||e.kind!=label||!e.named){MessageBox.Show("请先搜索并选中一项已核对名称的"+label+"。","选择条目");return;}
        Edit(kind,e.id.ToString(),level,e.name+"（"+e.id+"） → "+(kind=="avatar"?level+"命":"精炼"+level));
    }
    void AddSelectedWeapon() {
        if(busy)return;var e=Selection();
        if(e==null||e.kind!="武器"||!e.named){MessageBox.Show("请先搜索并选中一项已核对名称的武器。","选择武器");return;}
        string details=e.name+"（"+e.id+"）\n额外新增 "+(int)weaponQuantity.Value+" 把 · 等级 "+(int)weaponLevel.Value+" · 精炼 "+(int)refinement.Value;
        if(MessageBox.Show(details+"\n\n已有副本及装备不变，不消耗材料。请保持UID10001在线，等待完成期间不要同时发放同一武器。继续吗？","新增武器副本",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
        Run("weapon-control.ps1","-RequestId "+Guid.NewGuid().ToString("N")+" -ItemId "+e.id+" -Level "+(int)weaponLevel.Value+" -Refinement "+(int)refinement.Value+" -Quantity "+(int)weaponQuantity.Value,false,true);
    }
    void FilteredEdit(string kind,int level) {
        string label=kind=="avatar"?"角色":"武器";
        var ids=table.Rows.Cast<DataGridViewRow>().Select(r=>r.Tag as IdEntry).Where(e=>e!=null&&e.named&&e.kind==label).Select(e=>e.id).Distinct().ToList();
        if(ids.Count==0){MessageBox.Show("当前筛选结果中没有已核对名称的"+label+"。","筛选结果");return;}
        Edit(kind,String.Join(",",ids),level,"仅当前筛选内的 "+ids.Count+" 种"+label+" → "+(kind=="avatar"?level+"命":"精炼"+level));
    }
    void Edit(string kind,string selector,int level,string description) {
        if(busy)return;
        string text=description+"\n\n只修改已拥有内容，不新增角色/武器，不消耗材料。\n保留等级、基础天赋、装备和圣遗物。武器同ID全部副本生效；无精炼属性的武器跳过。\n每次有变更都会在E盘保存原命座/精炼，支持撤销。\n降低命座可能短暂重载当前场景。请保持UID10001在线，操作完成前不要同时手动发放或强化。继续吗？";
        if(MessageBox.Show(text,"确认本地存档修改",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
        Run("edit-content.ps1","-Kind "+kind+" -Selector \""+selector+"\" -Level "+level,true);
    }
    void Undo() {
        if(busy)return;
        if(MessageBox.Show("恢复上一次操作涉及的命座/精炼，不恢复角色等级或其他游戏进度。\n若这些条目的命座/精炼后来又变过，或旅行者切换了元素，撤销会停止并保留现状。\n请保持UID10001在线。继续吗？","撤销上一次修改",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
        Run("edit-content.ps1","-Kind restore -Selector last",true);
    }
    void Grant(string action) {
        if(busy)return;
        if(MessageBox.Show("请确认localtest（UID10001）已经进入世界。\n只补齐缺少内容：新角色90级/0命/基础天赋9级，新武器90级/精1/每种一把。\n已有角色配置和同ID武器跳过，未确认名称的内部条目不发放。\n操作完成前不要同时手动发放。继续吗？","确认补齐",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
        Run("client-control.ps1","-Action "+action,false);
    }
    void Run(string script,string arguments,bool edit,bool weapon=false) {
        busy=true;foreach(var b in actionButtons)b.Enabled=false;artifactDesigner.SetExternalBusy(true);artifactSetDesigner.SetExternalBusy(true);
        status.Text=edit?"正在备份、修改并等待服务端确认，请保持游戏在线。":weapon?"正在新增武器副本并核对实际数量，请保持游戏在线。":"正在补齐并核对存档；较多内容可能需要几分钟。";
        var worker=new BackgroundWorker();worker.DoWork+=delegate(object sender,DoWorkEventArgs e){
            var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32\\WindowsPowerShell\\v1.0\\powershell.exe"),"-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"scripts",script)+"\" "+arguments){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=root,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8};
            using(var p=Process.Start(info)) {
                Task<string> output=p.StandardOutput.ReadToEndAsync(),error=p.StandardError.ReadToEndAsync();p.WaitForExit();
                string all=output.Result+Environment.NewLine+error.Result;string log=Path.Combine(root,edit?"logs\\edit-content-ui.log":weapon?"logs\\weapon-grant-ui.log":"logs\\content-sync-ui.log");File.WriteAllText(log,all,Encoding.UTF8);
                if(p.ExitCode!=0)throw new Exception("操作遇到问题，请查看下面的具体原因。\n"+all.Substring(0,Math.Min(all.Length,1100))+"\n日志："+log);
                e.Result=output.Result;
            }
        };
        worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e){
            busy=false;foreach(var b in actionButtons)b.Enabled=true;artifactDesigner.SetExternalBusy(false);artifactSetDesigner.SetExternalBusy(false);RefreshRows();
            if(e.Error!=null)MessageBox.Show(e.Error.Message,"操作结果",MessageBoxButtons.OK,MessageBoxIcon.Warning);
            else if(edit) {
                try {
                    var result=new JavaScriptSerializer().Deserialize<EditReceipt>(((string)e.Result).Trim());
                    string message="完成：修改 "+result.changed+" 项；已是目标值 "+result.unchanged+" 项；不支持的条目跳过 "+result.skipped+" 项。\n没有重新发放角色或武器。";
                    if(!String.IsNullOrEmpty(result.backup))message+="\n原值备份："+Path.Combine(root,"backups\\edits",result.backup+".json");
                    MessageBox.Show(message,"命座/精炼修改结果",MessageBoxButtons.OK,MessageBoxIcon.Information);
                }catch(Exception ex){MessageBox.Show("服务端已返回，请查看修改日志："+ex.Message,"结果日志");}
            } else if(weapon) {
                try {
                    var receipt=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(((string)e.Result).Trim());
                    if(!Convert.ToBoolean(receipt["ok"])||!Convert.ToBoolean(receipt["verifiedSaved"]))throw new Exception("服务端结果尚未确认");
                    status.Text="完成：已核对新增 "+receipt["added"]+" 把武器，已有副本和装备未修改。";
                }catch(Exception ex){status.Text="结果尚未确认，请查看 weapon-grant-ui.log，不要重复发放。";MessageBox.Show(ex.Message,"武器结果核对");}
            } else MessageBox.Show("补齐完成。已有配置和同ID武器已跳过，请在游戏角色/背包界面查看。","补齐结果",MessageBoxButtons.OK,MessageBoxIcon.Information);
            worker.Dispose();
        };worker.RunWorkerAsync();
    }
    [STAThread] static void Main(string[] args) {Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);try{var form=new IdLookup();if(args.Contains("--artifacts"))form.tabs.SelectedIndex=1;if(args.Contains("--artifact-set"))form.tabs.SelectedIndex=2;Application.Run(form);}catch(Exception e){MessageBox.Show(e.Message,"管理工具启动问题",MessageBoxButtons.OK,MessageBoxIcon.Error);}}
}

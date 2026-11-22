using System;
using System.Linq;
using System.Reflection;
using System.Drawing;
using System.Windows.Forms;
class WeaponCopiesGuiTest {
    static int checks;
    static object Get(object o,string key){return o.GetType().GetField(key,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(o);}
    static void Check(bool value,string message){checks++;if(!value)throw new Exception(message);}
    [STAThread] static int Main(){
        try{
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            using(var f=new IdLookup()){
                var category=(ComboBox)Get(f,"category");category.SelectedIndex=4;
                var qty=(NumericUpDown)Get(f,"weaponQuantity");var level=(NumericUpDown)Get(f,"weaponLevel");var refine=(NumericUpDown)Get(f,"refinement");
                Check(qty.Minimum==1&&qty.Maximum==100&&qty.Value==1,"Copy range/default");
                Check(level.Minimum==1&&level.Maximum==90,"Level range");
                qty.Value=3;level.Value=90;refine.Value=5;
                var command=(TextBox)Get(f,"command");Check(command.Text.EndsWith("lv90 r5 x3"),"Selected command reflects count/level/refinement");
                qty.Value=7;Check(command.Text.EndsWith("x7"),"Count reacts to edits");
                category.SelectedIndex=1;Check(!command.Text.EndsWith("x7"),"Avatar commands are not changed to weapon copy count");
                category.SelectedIndex=4;qty.Value=3;f.ShowInTaskbar=false;f.StartPosition=FormStartPosition.Manual;f.Location=new Point(-20000,-20000);f.Show();Application.DoEvents();f.PerformLayout();
                Check(qty.Visible&&qty.Bottom<qty.Parent.ClientSize.Height,"New quantity row visible without clipping");
                using(var image=new Bitmap(f.Width,f.Height)){f.DrawToBitmap(image,new Rectangle(0,0,image.Width,image.Height));image.Save("E:\\Genshin-Local-Server\\audit\\weapon-copies-ui.png");}
                f.Close();
            }
            Console.WriteLine("PASS "+checks+" GUI checks; no buttons clicked, grants or live changes.");return 0;
        }catch(Exception e){Console.Error.WriteLine(e);return 1;}
    }
}

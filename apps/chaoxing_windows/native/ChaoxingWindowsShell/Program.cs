using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Web.WebView2.WinForms;

namespace ChaoxingWindowsShell;

internal static class Program
{
    private const string MutexName = "ChaoxingTodo.SingleInstance";

    [STAThread]
    private static void Main(string[] args)
    {
        using var mutex = new Mutex(true, MutexName, out var created);
        if (!created)
        {
            return;
        }

        ApplicationConfiguration.Initialize();
        var hidden = args.Contains("--hidden", StringComparer.OrdinalIgnoreCase);
        Application.Run(new ShellForm(hidden));
    }
}

internal sealed class ShellForm : Form
{
    private readonly NotifyIcon tray;
    private readonly ContextMenuStrip menu;
    private bool allowClose;

    public ShellForm(bool hidden)
    {
        Text = "学习通待办";
        Width = 420;
        Height = 640;
        ShowInTaskbar = !hidden;
        menu = new ContextMenuStrip();
        menu.Items.Add("打开窗口", null, (_, _) => ShowMain());
        menu.Items.Add("立即同步", null, (_, _) => { });
        menu.Items.Add("暂停通知", null, (_, _) => { });
        menu.Items.Add("查看登录状态", null, (_, _) => ShowMain());
        menu.Items.Add("退出", null, (_, _) =>
        {
            allowClose = true;
            Close();
        });
        tray = new NotifyIcon
        {
            Text = "学习通待办",
            Visible = true,
            ContextMenuStrip = menu,
            Icon = SystemIcons.Application,
        };
        tray.DoubleClick += (_, _) => ShowMain();
        if (hidden)
        {
            WindowState = FormWindowState.Minimized;
            Load += (_, _) => Hide();
        }
    }

    private void ShowMain()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!allowClose)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        tray.Visible = false;
        tray.Dispose();
        base.OnFormClosing(e);
    }
}

internal sealed class WebView2LoginForm : Form
{
    public WebView2LoginForm()
    {
        Text = "登录学习通";
        Width = 480;
        Height = 720;
        var web = new WebView2 { Dock = DockStyle.Fill };
        Controls.Add(web);
        Load += async (_, _) =>
        {
            await web.EnsureCoreWebView2Async();
            web.CoreWebView2.NavigationStarting += (_, args) =>
            {
                if (!args.Uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
                    !(args.Uri.Contains("chaoxing.com", StringComparison.OrdinalIgnoreCase) ||
                      args.Uri.Contains("chaoxing.com.cn", StringComparison.OrdinalIgnoreCase)))
                {
                    args.Cancel = true;
                }
            };
            web.CoreWebView2.Navigate(
                "https://passport2.chaoxing.com/login?fid=&refer=https%3A%2F%2Fi.chaoxing.com");
        };
    }
}

internal static class AutostartRegistry
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "ChaoxingTodo";

    public static void SetEnabled(bool enabled, string command)
    {
        using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RunKey);
        if (key is null)
        {
            throw new InvalidOperationException("开机自启注册失败");
        }
        if (enabled)
        {
            key.SetValue(ValueName, command);
        }
        else
        {
            key.DeleteValue(ValueName, false);
        }
    }
}

internal static class ToastNotifier
{
    public static void Show(string title, string body)
    {
        var script = $"New-BurntToastNotification -Text '{title.Replace("'", "''")}', '{body.Replace("'", "''")}'";
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "powershell",
                Arguments = $"-NoProfile -Command \"[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null\"",
                UseShellExecute = false,
                CreateNoWindow = true,
            });
        }
        catch
        {
            // Visible failure is handled by the TypeScript host when show() returns false.
        }
    }
}

internal static class DpapiStore
{
    public static byte[] Protect(byte[] plain) =>
        System.Security.Cryptography.ProtectedData.Protect(
            plain,
            null,
            System.Security.Cryptography.DataProtectionScope.CurrentUser);

    public static byte[] Unprotect(byte[] secret) =>
        System.Security.Cryptography.ProtectedData.Unprotect(
            secret,
            null,
            System.Security.Cryptography.DataProtectionScope.CurrentUser);
}

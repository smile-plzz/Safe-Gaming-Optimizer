using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Win32;

namespace SafeGamingOptimizer;

internal sealed class OptimizerService
{
    private static readonly Dictionary<string, ProcessRule> Rules = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Discord"] = new(SafetyLevel.Recommended, "Chat client. It can be reopened after gaming."),
        ["Spotify"] = new(SafetyLevel.Recommended, "Music client and helpers. Playback will stop."),
        ["Teams"] = new(SafetyLevel.Recommended, "Legacy Teams client. Calls and notifications will stop."),
        ["ms-teams"] = new(SafetyLevel.Recommended, "Teams client. Calls and notifications will stop."),
        ["slack"] = new(SafetyLevel.Recommended, "Chat client. It can be reopened after gaming."),
        ["WhatsApp"] = new(SafetyLevel.Recommended, "Desktop messaging client. It can be reopened after gaming."),
        ["Telegram"] = new(SafetyLevel.Recommended, "Desktop messaging client. It can be reopened after gaming."),
        ["PhoneExperienceHost"] = new(SafetyLevel.Recommended, "Windows Phone Link background app."),
        ["Widgets"] = new(SafetyLevel.Recommended, "Windows widgets panel and feed."),
        ["WidgetService"] = new(SafetyLevel.Recommended, "Windows widgets helper."),
        ["chrome"] = new(SafetyLevel.Review, "Browser. Closing can interrupt downloads, forms, or private sessions."),
        ["msedge"] = new(SafetyLevel.Review, "Browser. Closing can interrupt downloads, forms, or private sessions."),
        ["firefox"] = new(SafetyLevel.Review, "Browser. Closing can interrupt downloads, forms, or private sessions."),
        ["opera"] = new(SafetyLevel.Review, "Browser. Closing can interrupt downloads, forms, or private sessions."),
        ["brave"] = new(SafetyLevel.Review, "Browser. Closing can interrupt downloads, forms, or private sessions."),
        ["HD-Player"] = new(SafetyLevel.Review, "Android emulator. Close it only if no app or game is using it."),
        ["obs64"] = new(SafetyLevel.Review, "Recording/streaming app. Keep it if you plan to record gameplay."),
        ["OneDrive"] = new(SafetyLevel.Review, "File sync. Stopping it pauses uploads and downloads."),
        ["Dropbox"] = new(SafetyLevel.Review, "File sync. Stopping it pauses uploads and downloads."),
    };

    private static readonly HashSet<string> ProtectedNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "System", "Idle", "Registry", "smss", "csrss", "wininit", "winlogon", "services", "lsass",
        "svchost", "dwm", "explorer", "sihost", "taskhostw", "fontdrvhost", "audiodg", "conhost",
        "SecurityHealthService", "SecurityHealthSystray", "MsMpEng", "NisSrv", "WmiPrvSE", "spoolsv",
        "SearchIndexer", "StartMenuExperienceHost", "ShellExperienceHost", "RuntimeBroker", "ctfmon",
        "SafeGamingOptimizer", "powershell", "pwsh", "cmd"
    };

    private readonly string dataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SafeGamingOptimizer");
    private string SessionPath => Path.Combine(dataDirectory, "active-session.json");
    public bool HasActiveSession => File.Exists(SessionPath) && !(LoadSession()?.Restored ?? true);

    public OptimizerService() => Directory.CreateDirectory(dataDirectory);

    public static List<string> RunSelfTests()
    {
        var failures = new List<string>();
        if (Rules.Count < 10) failures.Add("Expected a useful optional-app rule set.");
        if (!Rules.Values.Any(r => r.Level == SafetyLevel.Recommended)) failures.Add("No Recommended rules exist.");
        if (!Rules.Values.Any(r => r.Level == SafetyLevel.Review)) failures.Add("No Review rules exist.");
        foreach (var dangerous in new[] { "explorer", "svchost", "MsMpEng", "lsass", "dwm" })
        {
            if (Rules.ContainsKey(dangerous)) failures.Add($"Protected process appears in optional rules: {dangerous}");
            if (!ProtectedNames.Contains(dangerous)) failures.Add($"Protected process guard is missing: {dangerous}");
        }
        if (Rules["chrome"].Level != SafetyLevel.Review) failures.Add("Browsers must require review.");
        if (Rules["OneDrive"].Level != SafetyLevel.Review) failures.Add("Cloud sync must require review.");
        return failures;
    }

    public List<ProcessCandidate> Analyze()
    {
        var result = new List<ProcessCandidate>();
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    ProcessRule rule;
                    if (process.Id == Environment.ProcessId || ProtectedNames.Contains(process.ProcessName))
                        continue;
                    if (!Rules.TryGetValue(process.ProcessName, out rule!))
                        continue;
                    result.Add(ProcessCandidate.From(process, rule));
                }
                catch { }
            }
        }
        return result.OrderBy(c => c.Safety).ThenByDescending(c => c.MemoryMb).ToList();
    }

    public async Task<(SessionState State, double FreedMb, List<string> Warnings)> OptimizeAsync(IEnumerable<ProcessCandidate> selected, IProgress<string>? progress = null)
    {
        if (HasActiveSession) throw new InvalidOperationException("A gaming session is already active. Finish or restore it first.");
        var choices = selected.Where(p => p.Selected && p.Safety != SafetyLevel.Protected).ToList();
        var state = new SessionState { StartedUtc = DateTime.UtcNow, OriginalPowerScheme = GetActivePowerScheme() };
        SaveSession(state);
        var warnings = new List<string>();
        double before = choices.Sum(p => p.MemoryMb);

        var high = FindHighPerformanceScheme();
        if (high is not null && high != state.OriginalPowerScheme)
        {
            if (RunPowerCfg("/setactive", high)) state.AppliedPowerScheme = high;
            else warnings.Add("Windows would not switch to the High performance power plan.");
            SaveSession(state);
        }

        foreach (var candidate in choices)
        {
            progress?.Report($"Closing {candidate.Name}...");
            try
            {
                using var process = Process.GetProcessById(candidate.Id);
                if (candidate.StartTimeUtc is not null && process.StartTime.ToUniversalTime() != candidate.StartTimeUtc) continue;
                state.StoppedProcesses.Add(new StoppedProcess { Name = candidate.Name, ExecutablePath = candidate.ExecutablePath, Restartable = candidate.Restartable });
                SaveSession(state);
                if (process.MainWindowHandle != IntPtr.Zero) process.CloseMainWindow();
                try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3)); } catch (TimeoutException) { }
                if (!process.HasExited)
                {
                    process.Kill(false);
                    await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3));
                }
            }
            catch (Exception ex) { warnings.Add($"{candidate.Name}: {ex.Message}"); }
        }

        EmptyWorkingSet(Process.GetCurrentProcess().Handle);
        SaveSession(state);
        await Task.Delay(800);
        double stillUsed = choices.Sum(c => TryWorkingSet(c.Id));
        return (state, Math.Max(0, Math.Round(before - stillUsed, 1)), warnings);
    }

    public List<string> Restore()
    {
        var state = LoadSession() ?? throw new InvalidOperationException("No saved gaming session was found.");
        if (state.Restored) return [];
        var warnings = new List<string>();
        if (state.AppliedPowerScheme is not null && state.OriginalPowerScheme is not null && !RunPowerCfg("/setactive", state.OriginalPowerScheme))
            warnings.Add("The original Windows power plan could not be restored.");

        var restarted = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in state.StoppedProcesses.Where(p => p.Restartable && p.ExecutablePath is not null))
        {
            if (!restarted.Add(item.ExecutablePath!)) continue;
            try
            {
                if (File.Exists(item.ExecutablePath) && !Process.GetProcessesByName(item.Name).Any())
                    Process.Start(new ProcessStartInfo(item.ExecutablePath) { UseShellExecute = true });
            }
            catch (Exception ex) { warnings.Add($"Could not reopen {item.Name}: {ex.Message}"); }
        }
        state.Restored = true;
        SaveSession(state);
        return warnings;
    }

    public (double UsedGb, double TotalGb, int ProcessCount) GetSystemSummary()
    {
        var status = new MemoryStatusEx();
        GlobalMemoryStatusEx(status);
        double total = status.TotalPhys / 1073741824d;
        double available = status.AvailPhys / 1073741824d;
        var processes = Process.GetProcesses();
        var count = processes.Length;
        foreach (var process in processes) process.Dispose();
        return (Math.Round(total - available, 1), Math.Round(total, 1), count);
    }

    private void SaveSession(SessionState state)
    {
        var temp = SessionPath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(state, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, SessionPath, true);
    }

    private SessionState? LoadSession()
    {
        try { return JsonSerializer.Deserialize<SessionState>(File.ReadAllText(SessionPath)); }
        catch { return null; }
    }

    private static double TryWorkingSet(int pid)
    {
        try { using var p = Process.GetProcessById(pid); return p.WorkingSet64 / 1048576d; }
        catch { return 0; }
    }

    private static string? GetActivePowerScheme()
    {
        var output = RunPowerCfgForOutput("/getactivescheme");
        return ExtractGuid(output);
    }

    private static string? FindHighPerformanceScheme()
    {
        var output = RunPowerCfgForOutput("/list");
        var line = output.Split('\n').FirstOrDefault(l => l.Contains("High performance", StringComparison.OrdinalIgnoreCase));
        return line is null ? null : ExtractGuid(line);
    }

    private static string? ExtractGuid(string text)
    {
        foreach (var word in text.Split([' ', '\r', '\n', ':'], StringSplitOptions.RemoveEmptyEntries))
            if (Guid.TryParse(word.Trim('*'), out var guid)) return guid.ToString();
        return null;
    }

    private static bool RunPowerCfg(params string[] args)
    {
        try { using var p = Process.Start(new ProcessStartInfo("powercfg.exe", string.Join(' ', args)) { UseShellExecute = false, CreateNoWindow = true }); p!.WaitForExit(); return p.ExitCode == 0; }
        catch { return false; }
    }

    private static string RunPowerCfgForOutput(string arg)
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo("powercfg.exe", arg) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true });
            var output = p!.StandardOutput.ReadToEnd(); p.WaitForExit(); return output;
        }
        catch { return ""; }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx([In, Out] MemoryStatusEx buffer);

    [DllImport("psapi.dll")]
    private static extern bool EmptyWorkingSet(IntPtr process);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private sealed class MemoryStatusEx
    {
        public uint Length = (uint)Marshal.SizeOf<MemoryStatusEx>();
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }
}

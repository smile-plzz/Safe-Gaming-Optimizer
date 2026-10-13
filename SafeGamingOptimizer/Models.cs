using System.Diagnostics;

namespace SafeGamingOptimizer;

internal enum SafetyLevel { Recommended, Review, Protected }

internal sealed record ProcessRule(SafetyLevel Level, string Reason, bool Restartable = true);

internal sealed class ProcessCandidate
{
    public bool Selected { get; set; }
    public string Name { get; init; } = "";
    public int Id { get; init; }
    public double MemoryMb { get; init; }
    public double CpuSeconds { get; init; }
    public SafetyLevel Safety { get; init; }
    public string Reason { get; init; } = "";
    public string? ExecutablePath { get; init; }
    public DateTime? StartTimeUtc { get; init; }
    public bool Restartable { get; init; }

    public static ProcessCandidate From(Process process, ProcessRule rule)
    {
        string? path = null;
        DateTime? started = null;
        try { path = process.MainModule?.FileName; } catch { }
        try { started = process.StartTime.ToUniversalTime(); } catch { }
        double cpu = 0;
        try { cpu = process.TotalProcessorTime.TotalSeconds; } catch { }
        return new ProcessCandidate
        {
            Selected = rule.Level == SafetyLevel.Recommended,
            Name = process.ProcessName,
            Id = process.Id,
            MemoryMb = Math.Round(process.WorkingSet64 / 1048576d, 1),
            CpuSeconds = Math.Round(cpu, 1),
            Safety = rule.Level,
            Reason = rule.Reason,
            ExecutablePath = path,
            StartTimeUtc = started,
            Restartable = rule.Restartable && path is not null
        };
    }
}

internal sealed class SessionState
{
    public DateTime StartedUtc { get; set; }
    public string? OriginalPowerScheme { get; set; }
    public string? AppliedPowerScheme { get; set; }
    public List<StoppedProcess> StoppedProcesses { get; set; } = [];
    public bool Restored { get; set; }
}

internal sealed class StoppedProcess
{
    public string Name { get; set; } = "";
    public string? ExecutablePath { get; set; }
    public bool Restartable { get; set; }
}

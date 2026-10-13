using System.ComponentModel;
using System.Drawing.Drawing2D;

namespace SafeGamingOptimizer;

internal sealed class MainForm : Form
{
    private readonly OptimizerService service = new();
    private readonly BindingList<ProcessCandidate> candidates = [];
    private readonly DataGridView grid = new();
    private readonly Label summary = new();
    private readonly Label status = new();
    private readonly Button optimize = new();
    private readonly Button finish = new();
    private readonly NotifyIcon tray = new();
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 3000 };
    private bool allowClose;

    public MainForm()
    {
        Text = "Safe Gaming Optimizer";
        MinimumSize = new Size(900, 620);
        Size = new Size(1080, 720);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(13, 18, 28);
        ForeColor = Color.WhiteSmoke;
        Font = new Font("Segoe UI", 10);

        var header = new Label { Text = "SAFE GAMING OPTIMIZER", Font = new Font("Segoe UI Semibold", 21), ForeColor = Color.FromArgb(104, 231, 176), Dock = DockStyle.Top, Height = 52, Padding = new Padding(20, 12, 0, 0) };
        summary.Dock = DockStyle.Top; summary.Height = 46; summary.Padding = new Padding(22, 5, 0, 0); summary.ForeColor = Color.FromArgb(190, 201, 218);
        var note = new Label { Text = "Recommended items are selected automatically. Review items may contain unsaved work. Windows, security, driver, launcher, and unknown processes are excluded.", Dock = DockStyle.Top, Height = 50, Padding = new Padding(22, 8, 20, 0), ForeColor = Color.FromArgb(162, 174, 194) };

        grid.Dock = DockStyle.Fill;
        grid.AutoGenerateColumns = false;
        grid.DataSource = candidates;
        grid.BackgroundColor = Color.FromArgb(18, 25, 38);
        grid.BorderStyle = BorderStyle.None;
        grid.GridColor = Color.FromArgb(43, 54, 72);
        grid.RowHeadersVisible = false;
        grid.AllowUserToAddRows = false;
        grid.AllowUserToDeleteRows = false;
        grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        grid.AutoSizeRowsMode = DataGridViewAutoSizeRowsMode.AllCells;
        grid.DefaultCellStyle.BackColor = Color.FromArgb(18, 25, 38);
        grid.DefaultCellStyle.ForeColor = Color.WhiteSmoke;
        grid.DefaultCellStyle.SelectionBackColor = Color.FromArgb(38, 71, 79);
        grid.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(28, 37, 52);
        grid.ColumnHeadersDefaultCellStyle.ForeColor = Color.WhiteSmoke;
        grid.EnableHeadersVisualStyles = false;
        grid.Columns.Add(new DataGridViewCheckBoxColumn { DataPropertyName = nameof(ProcessCandidate.Selected), HeaderText = "Stop", Width = 55 });
        grid.Columns.Add(new DataGridViewTextBoxColumn { DataPropertyName = nameof(ProcessCandidate.Name), HeaderText = "Process", Width = 160, ReadOnly = true });
        grid.Columns.Add(new DataGridViewTextBoxColumn { DataPropertyName = nameof(ProcessCandidate.MemoryMb), HeaderText = "RAM (MB)", Width = 90, ReadOnly = true });
        grid.Columns.Add(new DataGridViewTextBoxColumn { DataPropertyName = nameof(ProcessCandidate.CpuSeconds), HeaderText = "CPU time", Width = 90, ReadOnly = true });
        grid.Columns.Add(new DataGridViewTextBoxColumn { DataPropertyName = nameof(ProcessCandidate.Safety), HeaderText = "Safety", Width = 110, ReadOnly = true });
        grid.Columns.Add(new DataGridViewTextBoxColumn { DataPropertyName = nameof(ProcessCandidate.Reason), HeaderText = "Why", AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill, ReadOnly = true });
        grid.CellBeginEdit += (_, e) => { if (candidates[e.RowIndex].Safety == SafetyLevel.Protected) e.Cancel = true; };
        grid.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0) return;
            e.CellStyle.ForeColor = candidates[e.RowIndex].Safety switch { SafetyLevel.Recommended => Color.FromArgb(104, 231, 176), SafetyLevel.Review => Color.FromArgb(255, 196, 92), _ => Color.FromArgb(155, 164, 181) };
        };

        var actions = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 82, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(16), BackColor = Color.FromArgb(18, 25, 38) };
        finish.Text = "Finish gaming & restore"; finish.Width = 210; finish.Height = 44; finish.Enabled = false; finish.Click += (_, _) => FinishSession(false);
        optimize.Text = "Optimize for gaming"; optimize.Width = 205; optimize.Height = 44; optimize.BackColor = Color.FromArgb(55, 185, 126); optimize.FlatStyle = FlatStyle.Flat; optimize.Click += Optimize_Click;
        var refresh = new Button { Text = "Analyze again", Width = 145, Height = 44, FlatStyle = FlatStyle.Flat }; refresh.Click += (_, _) => RefreshCandidates();
        actions.Controls.Add(finish); actions.Controls.Add(optimize); actions.Controls.Add(refresh);
        status.AutoEllipsis = true; status.Dock = DockStyle.Bottom; status.Height = 32; status.Padding = new Padding(22, 7, 0, 0); status.ForeColor = Color.FromArgb(162, 174, 194);

        Controls.Add(grid); Controls.Add(note); Controls.Add(summary); Controls.Add(header); Controls.Add(status); Controls.Add(actions);
        tray.Text = "Safe Gaming Optimizer"; tray.Icon = SystemIcons.Shield; tray.Visible = true; tray.DoubleClick += (_, _) => RestoreWindow();
        tray.ContextMenuStrip = new ContextMenuStrip();
        tray.ContextMenuStrip.Items.Add("Open", null, (_, _) => RestoreWindow());
        tray.ContextMenuStrip.Items.Add("Finish gaming and restore", null, (_, _) => FinishSession(false));
        timer.Tick += (_, _) => UpdateSummary(); timer.Start();
        FormClosing += MainForm_FormClosing;
        Resize += (_, _) => { if (WindowState == FormWindowState.Minimized && service.HasActiveSession) { Hide(); tray.ShowBalloonTip(1500, "Gaming session active", "The optimizer is still monitoring in the background.", ToolTipIcon.Info); } };

        Shown += (_, _) =>
        {
            if (service.HasActiveSession)
            {
                var answer = MessageBox.Show("An unfinished gaming session was found. Restore the previous Windows state now?", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (answer == DialogResult.Yes) FinishSession(false);
            }
            RefreshCandidates(); UpdateSummary();
        };
    }

    private void RefreshCandidates()
    {
        candidates.RaiseListChangedEvents = false; candidates.Clear();
        foreach (var item in service.Analyze()) candidates.Add(item);
        candidates.RaiseListChangedEvents = true; candidates.ResetBindings();
        status.Text = candidates.Count == 0 ? "No known optional background apps are running." : $"Found {candidates.Count} known background process instances. Nothing has been changed.";
        optimize.Enabled = !service.HasActiveSession;
        finish.Enabled = service.HasActiveSession;
    }

    private async void Optimize_Click(object? sender, EventArgs e)
    {
        grid.EndEdit();
        var selected = candidates.Where(c => c.Selected && c.Safety != SafetyLevel.Protected).ToList();
        if (selected.Count == 0) { MessageBox.Show("Select at least one Recommended or Review process.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
        if (selected.Any(c => c.Safety == SafetyLevel.Review))
        {
            var answer = MessageBox.Show("You selected one or more Review items. They may contain unsaved work or active downloads. Continue?", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (answer != DialogResult.Yes) return;
        }
        optimize.Enabled = false; grid.Enabled = false;
        try
        {
            var progress = new Progress<string>(message => status.Text = message);
            var result = await service.OptimizeAsync(selected, progress);
            finish.Enabled = true;
            status.Text = $"Gaming mode active. Approximately {result.FreedMb:N0} MB was released. Minimize this app and start your game.";
            var warning = result.Warnings.Count == 0 ? "" : "\n\nSome items were skipped:\n" + string.Join("\n", result.Warnings);
            MessageBox.Show($"Gaming mode is active. Approximately {result.FreedMb:N0} MB was released.\n\nStart your game now. When finished, return here and click ‘Finish gaming & restore’.{warning}", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            RefreshCandidates();
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); optimize.Enabled = true; }
        finally { grid.Enabled = true; }
    }

    private void FinishSession(bool exitAfter)
    {
        if (!service.HasActiveSession) { if (exitAfter) { allowClose = true; Close(); } return; }
        try
        {
            var warnings = service.Restore();
            status.Text = "Normal Windows state restored. Apps changed by this session were reopened where possible.";
            if (warnings.Count > 0) MessageBox.Show("Restoration finished with notes:\n\n" + string.Join("\n", warnings), Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            RefreshCandidates();
            if (exitAfter) { allowClose = true; Close(); }
        }
        catch (Exception ex) { MessageBox.Show("Restoration could not finish: " + ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }

    private void MainForm_FormClosing(object? sender, FormClosingEventArgs e)
    {
        if (allowClose) { tray.Visible = false; return; }
        if (!service.HasActiveSession) { tray.Visible = false; return; }
        var answer = MessageBox.Show("Have you completed gaming?\n\nYes: restore the normal state and exit.\nNo: keep the optimizer running in the background.", Text, MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
        if (answer == DialogResult.Yes) { e.Cancel = true; FinishSession(true); }
        else if (answer == DialogResult.No) { e.Cancel = true; Hide(); tray.ShowBalloonTip(1500, "Still running", "Return from the tray when your gaming session is finished.", ToolTipIcon.Info); }
        else e.Cancel = true;
    }

    private void RestoreWindow() { Show(); WindowState = FormWindowState.Normal; Activate(); }
    private void UpdateSummary()
    {
        var s = service.GetSystemSummary();
        summary.Text = $"RAM in use: {s.UsedGb:N1} / {s.TotalGb:N1} GB     •     Processes: {s.ProcessCount}     •     Session: {(service.HasActiveSession ? "GAMING MODE ACTIVE" : "Ready")}";
        optimize.Enabled = !service.HasActiveSession; finish.Enabled = service.HasActiveSession;
    }
}
